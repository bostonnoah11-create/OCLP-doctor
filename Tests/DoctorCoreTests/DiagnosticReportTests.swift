import Foundation
import Darwin
import Testing
@testable import DoctorCore

@Suite
struct DiagnosticReportTests {
    private let since = Date(timeIntervalSince1970: 1_792_195_200) // 2026-10-17 00:00 UTC
    private var until: Date { since.addingTimeInterval(86_400) }

    @Test
    func classicPanicUsesEmbeddedTimeAndWhitelistedSignature() async throws {
        let time = "2026-10-17 21:45:20.123 +0900"
        let document = """
        Date/Time: \(time)
        panic(cpu 2 caller 0xffffff1234567890): Wake transition timed out after 180 seconds while SECRET_USER /Users/SECRET_USER/PRIVATE
        UUID: SECRET-UUID
        """
        let scan = await collect(document)
        let event = try #require(scan.events.first)
        #expect(event.timestamp == DiagnosticReportCollector.parseTimestamp(time))
        #expect(event.title == "Wake transition timed out")
        #expect(event.detail.contains("180 seconds"))
        #expect(event.kind == .failure)
        #expect(event.severity == .error)
        #expect(!serialized(scan).contains("SECRET"))
        #expect(!serialized(scan).contains("0xffffff"))
        #expect(!serialized(scan).contains("/Users/"))
    }

    @Test
    func ipsHeaderAndBodyPreferBodyIncidentTime() async throws {
        let header = try json(["timestamp": "2026-10-17 22:00:00.00 +0900", "incident_id": "SECRET-UUID"])
        let body = try json(["date": "2026-10-17 21:45:20.00 +0900", "panicString": "Sleep Wake failure in EFI\n\nFailure code:: 0x12345678 0x87654321\nSECRET /Users/private",
                             "product": "SECRET_HARDWARE", "crashReporterKey": "SECRET_KEY"])
        let scan = await collect(header + "\n" + body)
        let event = try #require(scan.events.first)
        #expect(event.timestamp == DiagnosticReportCollector.parseTimestamp("2026-10-17T12:45:20Z"))
        #expect(event.title == "Sleep Wake failure in EFI")
        #expect(!serialized(scan).contains("SECRET"))
        #expect(!serialized(scan).contains("12345678"))
    }

    @Test
    func ipsCanUseHeaderTimestampWhenBodyHasNone() async throws {
        let header = try json(["timestamp": "2026-10-17 21:45:20 +0900"])
        let body = try json(["panicString": "panic(cpu 0 caller 0xABC): Sleep/Wake hang detected\nSECRET"])
        let scan = await collect(header + "\n" + body)
        #expect(scan.events.first?.title == "Sleep/Wake hang detected")
        #expect(scan.coverage.state == .available)
    }

    @Test
    func timezoneIsRequiredAndNumericOffsetsPreserveInstant() {
        #expect(DiagnosticReportCollector.parseTimestamp("2026-10-17 21:45:20 +0900") == DiagnosticReportCollector.parseTimestamp("2026-10-17T12:45:20Z"))
        #expect(DiagnosticReportCollector.parseTimestamp("2026-10-17 05:45:20 -0700") == DiagnosticReportCollector.parseTimestamp("2026-10-17T12:45:20Z"))
        #expect(DiagnosticReportCollector.parseTimestamp("2026-10-17 21:45:20") == nil)
        #expect(DiagnosticReportCollector.parseTimestamp("2026-10-17 SECRET +0900") == nil)
    }

    @Test
    func undatedFailureDoesNotUseFileModificationTime() async {
        let scan = await collect("Sleep Wake failure in EFI\nSECRET")
        #expect(scan.events.isEmpty)
        #expect(scan.coverage.state == .partial)
        #expect(scan.coverage.detail.contains("missing reliable timestamp: 1"))
    }

    @Test
    func eventsOutsideRequestedWindowAreNotReported() async {
        let old = await collect("Date: 2026-10-01 21:45:20 +0900\nSleep transition timed out after 180 seconds")
        let future = await collect("Date: 2026-11-01 21:45:20 +0900\nSleep transition timed out after 180 seconds")
        #expect(old.events.isEmpty)
        #expect(future.events.isEmpty)
        #expect(old.coverage.state == .available)
    }

    @Test
    func unrelatedErrorsAndQuotedPrivateFieldsAreNotSleepFailures() async throws {
        let documents = ["Date: 2026-10-17 21:45:20 +0900\nGPU error SECRET", try json([
            "date": "2026-10-17 21:45:20 +0900", "privateLog": "Sleep Wake failure in EFI",
            "panicString": "Unrelated panic in SECRET"
        ])]
        for document in documents {
            let scan = await collect(document)
            #expect(scan.events.isEmpty)
            #expect(!serialized(scan).contains("SECRET"))
        }
    }

    @Test
    func malformedAndOversizedReportsProducePartialCoverage() async {
        for data in [Data("{\"panicString\":\"Sleep Wake failure in EFI\"".utf8), Data([0xFF]), Data(repeating: 0, count: 1_048_577)] {
            let scan = await collect(data: data)
            #expect(scan.events.isEmpty)
            #expect(scan.coverage.state == .partial)
        }
    }

    @Test
    func noCandidatesDiffersFromInaccessibleDirectories() async {
        let empty = await DiagnosticReportCollector(reader: ReportFixtureReader(batch: .init())).collect(since: since, until: until)
        let unavailable = await DiagnosticReportCollector(reader: ReportFixtureReader(batch: .init(readableDirectories: 0, unreadableDirectories: 2))).collect(since: since, until: until)
        let missing = await DiagnosticReportCollector(reader: ReportFixtureReader(batch: .init(readableDirectories: 1, missingDirectories: 1))).collect(since: since, until: until)
        #expect(empty.events.isEmpty)
        #expect(empty.coverage.state == .available)
        #expect(empty.coverage.detail.contains("Candidates: 0"))
        #expect(empty.coverage.detail.contains("does not prove"))
        #expect(unavailable.coverage.state == .unavailable)
        #expect(missing.coverage.state == .partial)
    }

    @Test
    func collectorEnforcesCountAndTotalBytesEvenForInjectedReader() async {
        let largeUnrelated = DiagnosticReportDocument(location: .system, data: Data(repeating: 65, count: 1_048_576))
        let scan = await DiagnosticReportCollector(reader: ReportFixtureReader(batch: .init(documents: Array(repeating: largeUnrelated, count: 41), candidateCount: 41))).collect(since: since, until: until)
        #expect(scan.coverage.state == .partial)
        #expect(scan.coverage.evidence.first?.detail.contains("8388608 bytes inspected") == true)
        #expect(scan.events.isEmpty)
    }

    @Test
    func localReaderDoesNotRecurseOrFollowSymlinksAndCountsLimit() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("OCLPDoctorReports-\(UUID().uuidString)")
        let system = base.appendingPathComponent("system"), user = base.appendingPathComponent("user")
        try FileManager.default.createDirectory(at: system.appendingPathComponent("Retired"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        for index in 0..<43 { try Data("unrelated".utf8).write(to: system.appendingPathComponent("private-\(index).diag")) }
        try Data("Sleep Wake failure in EFI".utf8).write(to: system.appendingPathComponent("Retired/old.panic"))
        let target = base.appendingPathComponent("external.panic")
        try Data("Sleep Wake failure in EFI".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: user.appendingPathComponent("alias.panic"), withDestinationURL: target)
        let batch = LocalDiagnosticReportReader(systemDirectory: system, userDirectory: user).read(since: Date().addingTimeInterval(-60), until: Date())
        #expect(batch.candidateCount == 43)
        #expect(batch.documents.count == 40)
        #expect(batch.limitedFiles == 3)
        #expect(batch.readableDirectories == 2)
    }

    @Test
    func partialReadBeforeIOFailureStillConsumesSharedByteBudget() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("OCLPDoctorReadBudget-\(UUID().uuidString).diag")
        try Data(repeating: 65, count: 64).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var budget = 64
        var callCount = 0
        let outcome = LocalDiagnosticReportReader.readRegularFile(file, limit: 64, remainingBudget: &budget) { descriptor, buffer, requested in
            callCount += 1
            if callCount == 1 { return Darwin.read(descriptor, buffer, min(16, requested)) }
            errno = EIO
            return -1
        }
        #expect(outcome == .unreadable)
        #expect(budget == 48)
        // A subsequent read cannot spend more than the remaining shared allowance.
        let next = LocalDiagnosticReportReader.readRegularFile(file, limit: 64, remainingBudget: &budget)
        #expect(next == .tooLarge)
        #expect(budget == 0)
    }

    @Test
    func localReaderBoundsFileSizeAndUsesMtimeOnlyAsPrefilter() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("OCLPDoctorReports-\(UUID().uuidString)")
        let system = base.appendingPathComponent("system"), user = base.appendingPathComponent("user")
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try Data(repeating: 65, count: 1_048_577).write(to: system.appendingPathComponent("oversized.panic"))
        let old = system.appendingPathComponent("old.panic")
        try Data("unrelated".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: old.path)
        let batch = LocalDiagnosticReportReader(systemDirectory: system, userDirectory: user).read(since: Date().addingTimeInterval(-60), until: Date())
        #expect(batch.documents.isEmpty)
        #expect(batch.candidateCount == 1)
        #expect(batch.oversizedFiles == 1)
        #expect(batch.missingDirectories == 1)
    }

    private func collect(_ text: String) async -> DiagnosticReportScan { await collect(data: Data(text.utf8)) }
    private func collect(data: Data) async -> DiagnosticReportScan {
        await DiagnosticReportCollector(reader: ReportFixtureReader(batch: .init(documents: [.init(location: .user, data: data)], candidateCount: 1))).collect(since: since, until: until)
    }
    private func json(_ value: [String: Any]) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)!
    }
    private func serialized(_ scan: DiagnosticReportScan) -> String {
        let encoder = JSONEncoder()
        return String(data: try! encoder.encode(scan.events), encoding: .utf8)! + String(data: try! encoder.encode(scan.coverage), encoding: .utf8)!
    }
}

private struct ReportFixtureReader: DiagnosticReportReading {
    let batch: DiagnosticReportReadBatch
    func read(since: Date, until: Date) -> DiagnosticReportReadBatch { batch }
}
