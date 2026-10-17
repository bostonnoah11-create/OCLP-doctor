import Foundation
import Testing
@testable import DoctorCore

@Suite
struct SleepWakeTests {
    private let now = LogTimestamp.parse("2026-10-17T12:00:00Z")!

    @Test func chronologicalOrderingUsesExplicitTimezoneAndSevenDayWindow() async {
        let power = """
        2026-10-17 10:01:00 +0000 Wake                 Wake from Normal Sleep
        2026-10-17 20:00:00 +0900 Sleep                Entering Sleep state
        2026-10-10 12:00:00 +0000 DarkWake             DarkWake due to RTC
        2026-10-10 11:59:59 +0000 Wake                 Outside window
        2026-10-17 12:00:01 +0000 Wake                 Future record
        """
        let report = await collector(power: power).collect(now: now)
        #expect(report.events.map(\.kind) == [.sleep, .wake, .darkWake])
        #expect(report.events.first?.timestamp == LogTimestamp.parse("2026-10-17T11:00:00Z"))
        #expect(report.events.last?.timestamp == report.windowStart)
        #expect(report.windowEnd == now)
        #expect(report.windowStart == now.addingTimeInterval(-604_800))
    }

    @Test func wakeRequestsAndAssertionsAreNotWakeEventsOrCorrelationAnchors() async throws {
        let power = """
        2026-10-17 11:00:00 +0000 Wake Requests        Scheduled RTC wake
        2026-10-17 11:00:01 +0000 Assertions           Kernel sleep preventer
        """
        let unified = try record("2026-10-17T11:00:30Z", "GPU error reset", type: "Error")
        let report = await collector(power: power, unified: unified).collect(now: now)
        #expect(report.events.isEmpty)
        #expect(report.errorCount == 0)
    }

    @Test func routineDarkWakeRTCAndChangedMessagesAreNotErrors() async throws {
        let power = "2026-10-17 11:00:00 +0000 DarkWake             DarkWake from Normal Sleep due to RTC"
        let unified = try [
            record("2026-10-17T11:00:01Z", "DarkWake due to RTC", type: "Default"),
            record("2026-10-17 11:00:02.287976+0000", "PMRD: sleep aggressiveness changed", type: "Default"),
            record("2026-10-17T11:00:03Z", "WindowServer display configuration changed", type: "Default")
        ].joined(separator: "\n")
        let report = await collector(power: power, unified: unified).collect(now: now)
        #expect(report.events.count == 1)
        #expect(report.events.first?.kind == .darkWake)
        #expect(report.events.first?.severity == .information)
        #expect(report.errorCount == 0)
        #expect(report.section.item("sleepWakeErrors")?.status == .unknown)
    }

    @Test func explicitFailuresAndTypedSleepWakeErrorsAreRetained() async throws {
        let power = """
        2026-10-17 10:00:00 +0000 Sleep Failure        Transition was refused
        2026-10-17 10:01:00 +0000 Failure              Failure during wake
        """
        let unified = try [
            record("2026-10-17T11:00:00Z", "Wake transition timed out after 180 seconds", type: "Default"),
            record("2026-10-17T11:01:00Z", "Sleep policy could not be applied", type: "Error"),
            record("2026-10-17T11:02:00Z", "Wake controller reported invalid state", type: "Fault")
        ].joined(separator: "\n")
        let report = await collector(power: power, unified: unified).collect(now: now)
        #expect(report.events.count == 5)
        #expect(report.errorCount == 4)
        #expect(report.events.filter { $0.severity == .fault && $0.kind == .relatedRecord }.count == 1)
        #expect(report.events.filter { $0.kind == .failure }.count == 3)
        #expect(report.section.item("sleepWakeErrors")?.status == .attention)
    }

    @Test func benignCountersAndNegativeFailureStatementsAreIgnored() async throws {
        let unified = try [
            record("2026-10-17T11:00:00Z", "Wake complete error=0", type: "Error"),
            record("2026-10-17T11:00:01Z", "Sleep: no failure detected", type: "Fault"),
            record("2026-10-17T11:00:02Z", "Wake failures: 0", type: "Default"),
            record("2026-10-17T11:00:03Z", "Sleep errors=none", type: "Error"),
            record("2026-10-17T11:00:04Z", "Wake failed; error=0", type: "Error")
        ].joined(separator: "\n")
        let report = await collector(unified: unified).collect(now: now)
        #expect(report.events.count == 1)
        #expect(report.events.first?.detail.contains("Wake failed") == true)
    }

    @Test func graphicsErrorsRequireATemporalAnchorAndDoNotEstablishCause() async throws {
        let power = "2026-10-17 11:00:00 +0000 Wake                 Wake from Normal Sleep"
        let unified = try [
            record("2026-10-17T11:01:59Z", "GPU reset error", type: "Error"),
            record("2026-10-17T11:02:00Z", "Rendering engine stopped", type: "Fault", process: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"),
            record("2026-10-17T11:02:01Z", "GPU reset error too far away", type: "Error"),
            record("2026-10-17T11:00:01Z", "Disk write error", type: "Error")
        ].joined(separator: "\n")
        let report = await collector(power: power, unified: unified).collect(now: now)
        #expect(report.events.count == 3)
        #expect(report.errorCount == 1)
        #expect(report.events.filter { $0.severity == .fault && $0.kind == .relatedRecord }.count == 1)
        for event in report.events.filter({ $0.severity == .error }) {
            #expect(event.kind == .relatedError)
            #expect(event.correlation?.contains("temporal proximity only") == true)
            #expect(event.correlation?.contains("no causal link") == true)
        }
    }

    @Test func deniedAndMissingSourcesDoNotBecomeHealthy() async {
        let runner = SleepWakeRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stderr: "PRIVATE-USER", exitCode: 1),
            .sleepWakeLog: .init(command: .sleepWakeLog, stderr: "PRIVATE-USER", exitCode: nil, termination: .launchFailed),
            .sleepWakeRecentLog: .init(command: .sleepWakeRecentLog, stderr: "PRIVATE-USER", exitCode: nil, termination: .launchFailed)
        ])
        let reader = SleepWakeReportReader(batch: .init(readableDirectories: 0, missingDirectories: 1, unreadableDirectories: 1))
        let report = await SleepWakeCollector(runner: runner, reportCollector: DiagnosticReportCollector(reader: reader)).collect(now: now)
        #expect(report.events.isEmpty)
        #expect(report.sources.allSatisfy { $0.state == .unavailable })
        #expect(report.section.item("sleepWakeErrors")?.status == .unknown)
        #expect(report.hasIncompleteCoverage)
        #expect(!report.sources.contains { $0.detail.contains("PRIVATE-USER") })
    }

    @Test func completedFramebufferFaultTracesAreSourceLevelRecordsNotGraphicsErrors() async throws {
        let power = "2026-10-17 11:00:00 +0000 Wake                 Wake from Normal Sleep"
        let unified = try [
            record("2026-10-17T11:00:01Z", "IOAccelDisplayPipe::display_change_handler(IOFramebuffer) event=1", type: "Fault", process: "/kernel"),
            record("2026-10-17T11:00:02Z", "IOAccelDisplayPipe::display_change_handler completed event=1 taking 240 ns", type: "Fault", process: "/kernel"),
            record("2026-10-17T11:00:03Z", "AMD framebuffer event completed", type: "Fault", process: "/kernel"),
            record("2026-10-17T11:03:00Z", "IOFramebuffer display_change_handler completed", type: "Fault", process: "/kernel")
        ].joined(separator: "\n")
        let report = await collector(power: power, unified: unified).collect(now: now)
        #expect(report.events.count == 4)
        #expect(report.errorCount == 0)
        #expect(report.section.item("sleepWakeErrors")?.status == .unknown)
        for event in report.events.filter({ $0.severity == .fault }) {
            #expect(event.kind == .relatedRecord)
            #expect(event.title == "Fault-level graphics record near a power event")
            #expect(event.correlation?.contains("level alone does not prove a graphics failure") == true)
        }
    }

    @Test func displayPeripheralErrorsRemainErrorsAndExplicitFaultFailuresRemainFailures() async throws {
        let power = "2026-10-17 11:00:00 +0000 Wake                 Wake from Normal Sleep"
        let unified = try [
            record("2026-10-17T11:00:01Z", "AppleUSBIORequest Display iSight pipe stalled", type: "Error", process: "/kernel"),
            record("2026-10-17T11:00:02Z", "AppleUSBHostUserClient failed to open Display Audio provider exclusively opened", type: "Error", process: "/kernel"),
            record("2026-10-17T11:00:03Z", "AppleUSBHostUserClient failed to open Apple LED Cinema Display provider exclusively opened", type: "Error", process: "/kernel"),
            record("2026-10-17T11:00:04Z", "Wake transition timed out", type: "Fault", process: "/kernel"),
            record("2026-10-17T11:03:00Z", "AppleUSBHostUserClient failed to open Display Audio", type: "Error", process: "/kernel")
        ].joined(separator: "\n")
        let report = await collector(power: power, unified: unified).collect(now: now)
        #expect(report.events.count == 5)
        #expect(report.errorCount == 4)
        let peripheral = report.events.filter { $0.title == "Display peripheral error near a power event" }
        #expect(peripheral.count == 3)
        #expect(peripheral.allSatisfy { $0.kind == .relatedError && $0.severity == .error && $0.correlation?.contains("no causal link") == true })
        #expect(report.events.filter { $0.kind == .failure && $0.severity == .error }.count == 1)
    }

    @Test func faultOverflowRetainsErrorsAndUsefulWakeContext() async throws {
        let power = "2026-10-17 11:00:00 +0000 Wake                 Wake from Normal Sleep"
        var records = try (0..<600).map { index in
            try record(String(format: "2026-10-17T11:00:01.%03dZ", index), "IOAccelDisplayPipe completed taking 240 ns", type: "Fault", process: "/kernel")
        }
        records.append(try record("2026-10-17T10:59:59Z", "Wake transition failed", type: "Error"))
        let report = await collector(power: power, unified: records.joined(separator: "\n")).collect(now: now)
        #expect(report.events.count == 500)
        #expect(report.omittedEventCount == 102)
        #expect(report.errorCount == 1)
        #expect(report.events.filter { $0.severity == .fault }.count == 498)
        #expect(report.events.filter { $0.kind == .wake }.count == 1)
    }

    @Test func timeoutAndTruncatedTailStillProduceValidEvidenceWithPartialCoverage() async throws {
        let power = "2026-10-17 11:00:00 +0000 Wake                 Wake from Normal Sleep\ntruncated trailing fragment"
        let unified = try record("2026-10-17T11:00:01Z", "Wake transition failed", type: "Error") + "\n{broken"
        let runner = SleepWakeRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: power, exitCode: nil, termination: .timedOut, outputWasTruncated: true),
            .sleepWakeLog: .init(command: .sleepWakeLog, stdout: unified, exitCode: 0, outputWasTruncated: true)
        ])
        let report = await collector(runner: runner).collect(now: now)
        #expect(report.events.count == 2)
        #expect(report.sources.first { $0.id == "powerHistory" }?.state == .partial)
        #expect(report.sources.first { $0.id == "sleepWakeLog" }?.state == .partial)
        #expect(report.hasIncompleteCoverage)
    }

    @Test func emptySuccessfulReadsDoNotProveSuccessfulResume() async {
        let report = await collector().collect(now: now)
        #expect(report.events.isEmpty)
        #expect(report.sources.allSatisfy { $0.state == .available })
        #expect(report.section.item("sleepWakeErrors")?.status == .unknown)
        #expect(report.section.item("sleepWakeErrors")?.message.contains("does not prove") == true)
    }

    @Test func malformedRecordsAndMissingTimezoneAreNotInventedEvents() async throws {
        let unified = try record("2026-10-17 11:00:00", "Wake failed", type: "Error") + "\n{}\ninvalid json"
        let report = await collector(power: "unexpected output", unified: unified).collect(now: now)
        #expect(report.events.isEmpty)
        #expect(report.sources.first { $0.id == "powerHistory" }?.state == .unavailable)
        // The independent recent query succeeds with no records, so combined coverage is partial.
        #expect(report.sources.first { $0.id == "sleepWakeLog" }?.state == .partial)
    }

    @Test func recentQueryPreservesLatestWakeErrorsWhenHistoricalQueryTimesOut() async throws {
        let power = "2026-10-17 11:00:00 +0000 Wake                 Wake from Normal Sleep"
        let oldRecord = try record("2026-10-15T10:00:00Z", "Wake transition failed", type: "Error")
        let recentRecord = try record("2026-10-17T11:00:01Z", "AppleUSBIORequest Display iSight pipe stalled", type: "Error", process: "/kernel")
        let runner = SleepWakeRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: power),
            .sleepWakeLog: .init(command: .sleepWakeLog, stdout: oldRecord, exitCode: nil, termination: .timedOut),
            .sleepWakeRecentLog: .init(command: .sleepWakeRecentLog, stdout: recentRecord)
        ])
        let report = await collector(runner: runner).collect(now: now)
        #expect(report.events.count == 3)
        #expect(report.errorCount == 2)
        #expect(report.latestError?.timestamp == LogTimestamp.parse("2026-10-17T11:00:01Z"))
        #expect(report.latestError?.title == "Display peripheral error near a power event")
        #expect(report.sources.count == 3)
        let coverage = try #require(report.sources.first { $0.id == "sleepWakeLog" })
        #expect(coverage.state == .partial)
        #expect(coverage.detail.contains("Historical query (last seven days): Partial"))
        #expect(coverage.detail.contains("Recent query (last two hours): Available"))
        #expect(coverage.evidence.count == 2)
    }

    @Test func overlappingUnifiedQueriesDoNotDoubleCountIdenticalRecords() async throws {
        let row = try record("2026-10-17T11:00:00Z", "Wake transition failed", type: "Error")
        let runner = SleepWakeRunner(outputs: [
            .powerHistory: .init(command: .powerHistory),
            .sleepWakeLog: .init(command: .sleepWakeLog, stdout: row),
            .sleepWakeRecentLog: .init(command: .sleepWakeRecentLog, stdout: row)
        ])
        let report = await collector(runner: runner).collect(now: now)
        #expect(report.events.count == 1)
        #expect(report.errorCount == 1)
        #expect(report.sources.count == 3)
        #expect(report.sources.allSatisfy { $0.state == .available })
    }

    @Test func absentFailureStringAndSleepTypeQueriesDoNotBecomeTransitionFailures() async throws {
        let unified = try [
            record("2026-10-17T11:00:00Z", "PMRD: No sleep wake failure string", type: "Default"),
            record("2026-10-17T11:00:01Z", "PMRD: No sleep wake failure string", type: "Error"),
            record("2026-10-17T11:00:02Z", "Failed to get sleep type. rc:0xe00002c7", type: "Default"),
            record("2026-10-17T11:00:03Z", "Failed to get sleep type. rc:0xe00002c7", type: "Error"),
            record("2026-10-17T11:00:04Z", "Sleep/Wake hang detected", type: "Default"),
            record("2026-10-17T11:00:05Z", "Sleep transition timed out after 180 seconds", type: "Default"),
            record("2026-10-17T11:00:06Z", "Wake failed", type: "Default")
        ].joined(separator: "\n")
        let report = await collector(unified: unified).collect(now: now)
        #expect(report.events.count == 5)
        #expect(report.events.filter { $0.kind == .failure }.count == 3)
        #expect(report.events.filter { $0.severity == .warning && $0.kind == .relatedRecord }.count == 1)
        #expect(report.events.filter { $0.title == "Sleep/wake diagnostic query error" && $0.kind == .relatedError }.count == 1)
        #expect(!report.events.contains { $0.detail.contains("No sleep wake failure string") })
        for event in report.events.filter({ $0.title.contains("diagnostic query") }) {
            #expect(event.correlation?.contains("does not establish that a sleep or wake transition failed") == true)
        }
    }

    @Test func knownNDJSONCompletionTrailerIsMetadataRatherThanMalformedEvidence() async throws {
        let row = try record("2026-10-17T11:00:00Z", "Wake transition failed", type: "Error")
        for trailer in [#"{"count":1,"finished":true}"#, #"{"count":1,"finished":1}"#] {
            let report = await collector(unified: row + "\n" + trailer).collect(now: now)
            #expect(report.events.count == 1)
            #expect(report.sources.first { $0.id == "sleepWakeLog" }?.state == .available)
            #expect(report.sources.first { $0.id == "sleepWakeLog" }?.detail.contains("malformed or unrecognized lines: 0") == true)
        }
        let malformed = await collector(unified: row + "\n" + #"{"count":"invalid","finished":true}"#).collect(now: now)
        #expect(malformed.sources.first { $0.id == "sleepWakeLog" }?.state == .partial)
    }

    @Test func sandboxDenialForSleepProcessIsNotAPowerTransitionError() async throws {
        let unified = try [
            record("2026-10-17T11:00:00Z", "Sandbox: sleep(7710) deny(1) sysctl-read kern.iossupportversion", type: "Error", process: "/bin/sleep"),
            record("2026-10-17T11:00:01Z", "Sandbox: sleep(7711) deny(1) file-read-data /private/test", type: "Fault", process: "/kernel")
        ].joined(separator: "\n")
        let report = await collector(unified: unified).collect(now: now)
        #expect(report.events.isEmpty)
        #expect(report.errorCount == 0)
        #expect(report.sources.first { $0.id == "sleepWakeLog" }?.state == .available)
    }

    @Test func wakeReasonPermissionErrorsPreserveSeverityWithoutClaimingTransitionFailure() async throws {
        let unified = try [
            record("2026-10-17T11:00:00Z", "[1234] is not entitled to set wake reason", type: "Error"),
            record("2026-10-17T11:00:01Z", "[1234] is not entitled to set wake reason", type: "Fault"),
            record("2026-10-17T11:00:02Z", "[1234] is not entitled to set wake reason", type: "Default")
        ].joined(separator: "\n")
        let report = await collector(unified: unified).collect(now: now)
        #expect(report.events.count == 3)
        #expect(report.events.map(\.severity) == [.information, .fault, .error])
        #expect(report.events.allSatisfy { $0.title == "Wake-reason API permission error" && $0.kind != .failure })
        #expect(report.events.allSatisfy { $0.correlation?.contains("does not establish that a sleep or wake transition failed") == true })
    }

    @Test func sameSourceDuplicatesCollapseButCrossSourceRecordsRemainDistinct() async throws {
        let message = "Wake transition timed out"
        let line = "2026-10-17 11:00:00 +0000 Wake                 " + message
        let unified = try record("2026-10-17T11:00:00Z", message, type: "Error")
        let first = await collector(power: line + "\n" + line, unified: unified + "\n" + unified).collect(now: now)
        let second = await collector(power: line, unified: unified).collect(now: now)
        #expect(first.events.count == 2)
        #expect(first.errorCount == 2)
        #expect(Set(first.events.map(\.source)).count == 2)
        #expect(first.events.map(\.id) == second.events.map(\.id))
    }

    @Test func eventLimitPreservesOlderErrorsBeforeRecentContext() async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let power = (0..<600).map { index in
            formatter.string(from: now.addingTimeInterval(-Double(index + 1) * 10)) + " Sleep                Entering Sleep state"
        }.joined(separator: "\n")
        let unified = try record("2026-10-11T11:00:00Z", "Wake transition timed out", type: "Error")
        let report = await collector(power: power, unified: unified).collect(now: now)
        #expect(report.events.count == 500)
        #expect(report.omittedEventCount == 101)
        #expect(report.errorCount == 1)
        #expect(report.events.last?.severity == .error)
        #expect(report.hasIncompleteCoverage)
        #expect(zip(report.events, report.events.dropFirst()).allSatisfy { pair in pair.0.timestamp >= pair.1.timestamp })
    }

    @Test func errorOverflowRetainsNewestErrorRecords() async throws {
        let formatter = ISO8601DateFormatter()
        let unified = try (0..<510).map { index in
            try record(formatter.string(from: now.addingTimeInterval(-Double(index + 1))), "Wake transition failed", type: "Error")
        }.joined(separator: "\n")
        let report = await collector(unified: unified).collect(now: now)
        #expect(report.events.count == 500)
        #expect(report.errorCount == 500)
        #expect(report.omittedEventCount == 10)
        #expect(report.events.last?.timestamp == now.addingTimeInterval(-500))
    }

    @Test func privateLogFieldsPathsAndStderrAreNotExported() async throws {
        let message = "Wake failed path=/Users/PRIVATE-NAME/Documents/private.log username=PRIVATE-ACCOUNT pid=987654 serial=PRIVATE-SERIAL https://private.example/a user@example.com 12:34:56:78:9a:bc 12345678-1234-1234-1234-123456789abc"
        let unified = try record("2026-10-17T11:00:00Z", message, type: "Error", process: "/Users/PRIVATE-PROCESS/private.app/Contents/MacOS/private")
        let runner = SleepWakeRunner(outputs: [
            .powerHistory: .init(command: .powerHistory),
            .sleepWakeLog: .init(command: .sleepWakeLog, stdout: unified, stderr: "PRIVATE-STDERR")
        ])
        let report = await collector(runner: runner).collect(now: now)
        let text = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        #expect(report.events.count == 1)
        for forbidden in ["PRIVATE-NAME", "PRIVATE-ACCOUNT", "987654", "PRIVATE-SERIAL", "private.example", "user@example.com", "12:34:56:78:9a:bc", "12345678-1234-1234-1234-123456789abc", "PRIVATE-PROCESS", "PRIVATE-STDERR"] {
            #expect(!text.contains(forbidden), "Unexpected private value: \(forbidden)")
        }
    }

    @Test func detailIsBoundedAndDiagnosticReportsAreMergedAsEvidence() async throws {
        let unified = try record("2026-10-17T11:00:00Z", "Wake failed " + String(repeating: "x", count: 1_000), type: "Error")
        let data = Data("Date/Time: 2026-10-17 10:00:00 +0000\nSleep Wake failure in EFI\n".utf8)
        let reader = SleepWakeReportReader(batch: .init(documents: [.init(location: .system, data: data)], candidateCount: 1))
        let runner = SleepWakeRunner(outputs: [.powerHistory: .init(command: .powerHistory), .sleepWakeLog: .init(command: .sleepWakeLog, stdout: unified)])
        let report = await SleepWakeCollector(runner: runner, reportCollector: DiagnosticReportCollector(reader: reader)).collect(now: now)
        #expect(report.events.count == 2)
        #expect(report.events.allSatisfy { $0.detail.count <= 600 })
        #expect(report.events.contains { $0.source == "System DiagnosticReports" })
        #expect(report.sources.count == 3)
    }

    private func collector(power: String = "", unified: String = "") -> SleepWakeCollector {
        collector(runner: SleepWakeRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: power),
            .sleepWakeLog: .init(command: .sleepWakeLog, stdout: unified)
        ]))
    }

    private func collector(runner: SleepWakeRunner) -> SleepWakeCollector {
        SleepWakeCollector(runner: runner, reportCollector: DiagnosticReportCollector(reader: SleepWakeReportReader(batch: .init())))
    }

    private func record(_ timestamp: String, _ message: String, type: String, process: String = "/usr/libexec/powerd") throws -> String {
        let object = ["timestamp": timestamp, "eventMessage": message, "messageType": type, "processImagePath": process]
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
}

private struct SleepWakeRunner: CommandExecuting {
    let outputs: [DiagnosticCommand: CommandOutput]
    func run(_ command: DiagnosticCommand) async -> CommandOutput {
        outputs[command] ?? CommandOutput(command: command, exitCode: command == .sleepWakeRecentLog ? 0 : 1)
    }
    func runWakeBluetoothLog(since: Date, until: Date) async -> CommandOutput {
        outputs[.wakeBluetoothLog] ?? CommandOutput(command: .wakeBluetoothLog, windowStart: since, windowEnd: until)
    }
    func runWakeBluetoothLifecycleLog(since: Date, until: Date) async -> CommandOutput {
        outputs[.wakeBluetoothLifecycleLog] ?? CommandOutput(command: .wakeBluetoothLifecycleLog, windowStart: since, windowEnd: until)
    }
}

private struct SleepWakeReportReader: DiagnosticReportReading {
    let batch: DiagnosticReportReadBatch
    func read(since: Date, until: Date) -> DiagnosticReportReadBatch { batch }
}
