import Foundation
import Testing
@testable import DoctorCore

@Suite
struct LogTextTests {
    @Test func timestampsRequireAnExplicitTimezoneAndNormalizeOffsets() throws {
        let local = try #require(LogTimestamp.parse("2026-10-17 21:45:18 +0900"))
        let utc = try #require(LogTimestamp.parse("2026-10-17T12:45:18Z"))
        #expect(local == utc)
        #expect(LogTimestamp.parse("2026-10-17 21:45:18") == nil)
        #expect(LogTimestamp.parse("not a timestamp") == nil)
    }

    @Test func unifiedTimestampPreservesFractionalSeconds() throws {
        let date = try #require(LogTimestamp.parse("2026-10-17 12:45:18.014725+0000"))
        let whole = try #require(LogTimestamp.parse("2026-10-17T12:45:18Z"))
        #expect(abs(date.timeIntervalSince(whole) - 0.014725) < 0.002)
    }

    @Test func iso8601MillisecondsPreservesCompactFractionsAndUsesUTC() throws {
        #expect(LogTimestamp.iso8601Milliseconds(Date(timeIntervalSince1970: 1_792_241_152.673))
            == "2026-10-17T12:45:52.673Z")
        #expect(LogTimestamp.iso8601Milliseconds(Date(timeIntervalSince1970: 1_792_241_121.119))
            == "2026-10-17T12:45:21.119Z")
        let local = try #require(LogTimestamp.parse("2026-10-17 21:45:21.119 +0900"))
        #expect(LogTimestamp.iso8601Milliseconds(local) == "2026-10-17T12:45:21.119Z")
    }

    @Test func iso8601MillisecondsRoundsAcrossSecondAndMinuteBoundaries() {
        #expect(LogTimestamp.iso8601Milliseconds(Date(timeIntervalSince1970: 1_792_241_159.9996))
            == "2026-10-17T12:46:00.000Z")
        #expect(LogTimestamp.iso8601Milliseconds(Date(timeIntervalSince1970: 1_792_241_159.9994))
            == "2026-10-17T12:45:59.999Z")
        #expect(LogTimestamp.iso8601Milliseconds(Date(timeIntervalSince1970: 1_792_241_118))
            == "2026-10-17T12:45:18.000Z")
    }

    @Test func iso8601MillisecondsUsesNonnegativeFractionsBeforeUnixEpoch() {
        #expect(LogTimestamp.iso8601Milliseconds(Date(timeIntervalSince1970: -0.001))
            == "1969-12-31T23:59:59.999Z")
        #expect(LogTimestamp.iso8601Milliseconds(Date(timeIntervalSince1970: -0.0004))
            == "1970-01-01T00:00:00.000Z")
        #expect(LogTimestamp.iso8601Milliseconds(Date(timeIntervalSince1970: -1.0006))
            == "1969-12-31T23:59:58.999Z")
    }

    @Test func reusedTimestampParserKeepsMixedFormatsAndOffsetsIndependent() throws {
        let parser = LogTimestampParser()
        let whole = Date(timeIntervalSince1970: 1_792_241_118)
        let samples: [(String, TimeInterval)] = [
            ("2026-10-17 21:45:18 +0900", 0),
            ("2026-10-17T12:45:18.250Z", 0.25),
            ("2026-10-17 05:45:18-0700", 0),
            ("2026-10-17 12:45:18.014725+0000", 0.014725),
            ("2026-10-17T14:45:18+02:00", 0),
            ("2026-10-17 12:45:18.125 +0000", 0.125),
            ("2026-10-17T12:45:18Z", 0),
            ("  2026-10-17 21:45:18.750+0900\n", 0.75)
        ]
        for sample in samples + Array(samples.reversed()) {
            let date = try #require(parser.parse(sample.0))
            #expect(abs(date.timeIntervalSince(whole) - sample.1) < 0.002)
        }
    }

    @Test func reusedTimestampParserRejectsInvalidInputBetweenValidRecords() throws {
        let parser = LogTimestampParser()
        let expected = Date(timeIntervalSince1970: 1_792_241_118)
        let invalid = [
            "2026-10-17 21:45:18",
            "2026-10-17 12:45:18 +9999",
            "2026-10-17 12:45:18 +00:99",
            "2026-13-17 12:45:18 +0000",
            "2026-10-17 25:45:18 +0000",
            "2026-10-17 12:45:18 +0000 trailing text",
            "not a timestamp",
            String(repeating: "0", count: 81)
        ]
        for text in invalid {
            #expect(parser.parse("2026-10-17 21:45:18 +0900") == expected)
            #expect(parser.parse(text) == nil)
            let recovered = try #require(parser.parse("2026-10-17T12:45:18.500Z"))
            #expect(abs(recovered.timeIntervalSince(expected) - 0.5) < 0.002)
        }
    }

    @Test func privateLogFieldsAreRedactedAndControlCharactersCannotInjectRows() {
        let raw = "pid 733 WindowServer(7710) /Users/privateperson/secret.txt https://example.com/secret " +
            "F5D3E6F1-17CC-4711-BC78-127049F06F00 aa:bb:cc:dd:ee:ff 192.168.2.4 " +
            "person@example.com privatehost.local serial=PRIVATE_SERIAL token=PRIVATE_TOKEN\n\tWake failed"
        let result = LogRedactor.sanitize(raw)
        for secret in ["733", "7710", "privateperson", "example.com", "F5D3", "aa:bb", "192.168", "privatehost", "PRIVATE_SERIAL", "PRIVATE_TOKEN"] {
            #expect(!result.contains(secret))
        }
        #expect(!result.contains("\n"))
        #expect(!result.contains("\t"))
        #expect(result.contains("Wake failed"))
        #expect(!LogRedactor.sanitize("[1234] is not entitled to set wake reason").contains("1234"))
    }

    @Test func errorCodesAndUsefulDriverWordingSurvivePrivacyFiltering() {
        let result = LogRedactor.sanitize("AppleUSBIORequest::complete: Display iSight status 0xe0005000 (pipe stalled)")
        #expect(result.contains("AppleUSBIORequest::complete"))
        #expect(result.contains("0xe0005000"))
        #expect(result.contains("pipe stalled"))
        #expect(LogRedactor.sanitize(String(repeating: "a", count: 20_000)).count == 600)
    }

    @Test func alternateSerialKeysAndQuotedPathsAreRedacted() {
        let result = LogRedactor.sanitize("Wake failure IOPlatformSerialNumber=C02SECRET1234 Serial Number: C02OTHER1234 /tmp/SECRET_TOKEN/output.txt \"/Volumes/Private Backup/secret.pdf\"")
        for secret in ["C02SECRET", "C02OTHER", "SECRET_TOKEN", "Private Backup", "secret.pdf"] {
            #expect(!result.contains(secret))
        }
        #expect(result.contains("Wake failure"))
    }

    @Test func faultRecordsDoNotBecomeErrorCountsOrLatestErrors() {
        let date = Date(timeIntervalSince1970: 1_792_240_000)
        let record = SleepWakeEvent(id: "trace", timestamp: date, kind: .relatedRecord, severity: .fault,
            title: "Fault-level graphics record", detail: "completed", source: "Synthetic fixture", evidence: [])
        let report = SleepWakeReport(windowStart: date.addingTimeInterval(-60), windowEnd: date,
            events: [record], sources: [])
        #expect(report.errorCount == 0)
        #expect(report.faultCount == 1)
        #expect(report.latestError == nil)
        #expect(report.section.item("sleepWakeErrors")?.status == .unknown)
        let text = ReportGenerator.sleepWakeReport(report)
        #expect(text.contains("Fault-level records: 1"))
        #expect(text.contains("does not establish failure"))
    }
}
