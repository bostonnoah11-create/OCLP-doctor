import Foundation
import Testing
@testable import DoctorCore

@Suite
struct BluetoothTests {
    private let now = LogTimestamp.parse("2026-10-17T12:00:00Z")!
    private let wake = "2026-10-17 11:00:00 +0000 Wake                 Wake from Normal Sleep"

    @Test func incidentQueryPrecedesBroadHistoryAndUsesLatestFullWake() async throws {
        let power = wake + "\n2026-10-17 11:50:00 +0000 DarkWake             DarkWake due to RTC"
        let hci = try record("2026-10-17T10:56:00Z", "HCI command failure", process: "bluetoothd")
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: power),
            .wakeBluetoothLog: .init(command: .wakeBluetoothLog, stdout: hci),
            .sleepWakeLog: .init(command: .sleepWakeLog, exitCode: nil, termination: .timedOut)
        ])
        let report = await collector(runner).collect(now: now)
        let calls = await runner.calls
        #expect(calls.first == .powerHistory)
        let lastFocusedCall = try #require(calls.lastIndex { [.wakeIncidentLog, .wakeBluetoothLog, .wakeBluetoothLifecycleLog].contains($0) })
        #expect(calls.firstIndex(of: .sleepWakeLog)! > lastFocusedCall)
        #expect(calls.firstIndex(of: .sleepWakeRecentLog)! > lastFocusedCall)
        let focus = try #require(report.focusedWake)
        #expect(focus.wakeAt == LogTimestamp.parse("2026-10-17T11:00:00Z"))
        #expect(focus.start == LogTimestamp.parse("2026-10-17T10:55:00Z"))
        #expect(focus.end == LogTimestamp.parse("2026-10-17T11:02:00Z"))
        #expect(focus.events.first?.bluetoothEvent == .hciFailure)
        #expect(focus.coverage.state == .available)
        #expect(report.hasIncompleteCoverage)
    }

    @Test func incidentWindowEndsAtCollectionTimeWhenWakeIsRecent() async throws {
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: "2026-10-17 11:59:30 +0000 Wake                 Wake from Normal Sleep")
        ])
        let report = await collector(runner).collect(now: now)
        let focus = try #require(report.focusedWake)
        #expect(focus.start == now.addingTimeInterval(-330))
        #expect(focus.end == now)
        let windows = await runner.windows
        #expect(windows.count == 5)
        #expect(windows.allSatisfy { $0.0 >= focus.start && $0.1 <= focus.end && $0.0 < $0.1 })
        #expect(focus.events.isEmpty)
        #expect(focus.coverage.detail.contains("does not prove"))
    }

    @Test func explicitHCIAndLifecyclePreserveLevelsAndExcludePrivateText() async throws {
        let rows = try [
            record("2026-10-17T10:59:59Z", "HCI command failure device=PRIVATE-DEVICE 12:34:56:78:9a:bc", type: "Default", process: "bluetoothd"),
            record("2026-10-17T11:00:00Z", "HCI command timed out PRIVATE-DEVICE", type: "Fault", process: "bluetoothd"),
            record("2026-10-17T11:00:01Z", "HCI command error=12 PRIVATE-DEVICE", type: "Error", process: "bluetoothd"),
            record("2026-10-17T11:00:02Z", "[system/com.apple.bluetoothd [654321]:] exited due to SIGABRT PRIVATE-USER", type: "Default", process: "launchd"),
            record("2026-10-17T11:00:03Z", "[system/com.apple.bluetoothd:] spawned with pid 987654 PRIVATE-USER", type: "Info", process: "launchd"),
            record("2026-10-17T11:00:04Z", "Controller state: ready PRIVATE-DEVICE", type: "Info", process: "bluetoothd")
        ].joined(separator: "\n")
        let report = await collect(focused: rows)
        let focus = try #require(report.focusedWake)
        #expect(focus.events.count == 6)
        #expect(focus.events.filter { $0.bluetoothEvent == .hciFailure }.count == 3)
        #expect(focus.events.filter { $0.severity == .error }.count == 1)
        #expect(focus.events.filter { $0.severity == .fault }.count == 1)
        #expect(focus.events.filter { $0.severity == .information }.count == 4)
        #expect(focus.events.allSatisfy { $0.kind != .failure })
        #expect(focus.events.contains { $0.bluetoothEvent == .daemonExit })
        #expect(focus.events.contains { $0.bluetoothEvent == .daemonStart })
        #expect(focus.events.contains { $0.bluetoothEvent == .controllerReady })
        #expect(focus.events.allSatisfy { $0.correlation?.contains("temporal proximity only") == true })
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        for secret in ["PRIVATE-DEVICE", "PRIVATE-USER", "654321", "987654", "12:34:56:78:9a:bc"] {
            #expect(!json.contains(secret))
        }
    }

    @Test func unrelatedLaunchdRoutineHCIAndUncompletedStartsAreExcluded() async throws {
        let rows = try [
            record("2026-10-17T11:00:00Z", "HCI command complete error=0", type: "Error", process: "bluetoothd"),
            record("2026-10-17T11:00:01Z", "HCI command complete", process: "bluetoothd"),
            record("2026-10-17T11:00:02Z", "[system/com.apple.bluetoothd.helper:] exited", process: "launchd"),
            record("2026-10-17T11:00:03Z", "[system/com.apple.other:] exited wake failed", type: "Error", process: "launchd"),
            record("2026-10-17T11:00:04Z", "[system/com.apple.bluetoothd:] will spawn in 2 seconds", process: "launchd"),
            record("2026-10-17T11:00:05Z", "[system/com.apple.bluetoothd:] service state: spawning", process: "launchd"),
            record("2026-10-17T11:00:06Z", "HCI command failure", process: "unrelated"),
            record("2026-10-17T11:00:07Z", "Controller is not ready", process: "bluetoothd"),
            record("2026-10-17T11:00:08Z", "STARTED WIPROX DAEMON", process: "bluetoothd")
        ].joined(separator: "\n")
        let report = await collect(focused: rows)
        #expect(report.focusedWake?.events.isEmpty == true)
        #expect(report.events.map(\.kind) == [.wake])
    }

    @Test func bluetoothScopeRequiresFullWakeAndIncludesOnlyBoundedNeighbors() async throws {
        let rows = try [
            record("2026-10-17T10:54:59Z", "HCI command failure", process: "bluetoothd"),
            record("2026-10-17T10:55:00Z", "HCI command failure", process: "bluetoothd"),
            record("2026-10-17T11:02:00Z", "[system/com.apple.bluetoothd:] service state: running", process: "launchd"),
            record("2026-10-17T11:02:01Z", "HCI command failure", process: "bluetoothd")
        ].joined(separator: "\n")
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeIncidentLog: .init(command: .wakeIncidentLog, stdout: rows),
            .sleepWakeLog: .init(command: .sleepWakeLog, stdout: rows)
        ])
        let report = await collector(runner).collect(now: now)
        #expect(report.focusedWake?.events.count == 2)
        #expect(report.events.filter { $0.bluetoothEvent != nil }.count == 2)
        let darkRunner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake.replacingOccurrences(of: "Wake ", with: "DarkWake ")),
            .sleepWakeLog: .init(command: .sleepWakeLog, stdout: rows)
        ])
        let darkReport = await collector(darkRunner).collect(now: now)
        #expect(darkReport.focusedWake == nil)
        #expect(!darkReport.events.contains { $0.bluetoothEvent != nil })
        let darkCalls = await darkRunner.calls
        #expect(!darkCalls.contains(.wakeIncidentLog))
        #expect(!darkCalls.contains(.wakeBluetoothLog))
        #expect(!darkCalls.contains(.wakeBluetoothLifecycleLog))
    }

    @Test func incidentDeduplicationPreservesBluetoothMetadataAndLifecycleAcrossQueries() async throws {
        let rows = try [
            record("2026-10-17T10:59:59Z", "HCI command failure", type: "Error", process: "bluetoothd"),
            record("2026-10-17T11:00:01Z", "[system/com.apple.bluetoothd:] exited", process: "launchd"),
            record("2026-10-17T11:00:02Z", "[system/com.apple.bluetoothd:] service state: running", process: "launchd")
        ].joined(separator: "\n")
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeIncidentLog: .init(command: .wakeIncidentLog, stdout: rows),
            .sleepWakeLog: .init(command: .sleepWakeLog, stdout: rows),
            .sleepWakeRecentLog: .init(command: .sleepWakeRecentLog, stdout: rows)
        ])
        let report = await collector(runner).collect(now: now)
        #expect(report.events.count == 4)
        #expect(report.events.filter { $0.bluetoothEvent != nil }.count == 3)
        #expect(report.errorCount == 1)
        #expect(report.focusedWake?.events.count == 3)
    }

    @Test func opaqueIdentityRetainsDistinctHCIRecordsAtTheSameTimestampWithoutPrivateText() async throws {
        let first = try record("2026-10-17T11:00:00.123456Z", "HCI command failure PRIVATE-ONE", type: "Error", process: "bluetoothd")
        let second = try record("2026-10-17T11:00:00.123456Z", "HCI command failure PRIVATE-TWO", type: "Error", process: "bluetoothd")
        let otherLevel = try record("2026-10-17T11:00:00.123456Z", "HCI command failure PRIVATE-ONE", type: "Default", process: "bluetoothd")
        let rows = [first, second, otherLevel, first].joined(separator: "\n")
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeIncidentLog: .init(command: .wakeIncidentLog, stdout: rows),
            .sleepWakeLog: .init(command: .sleepWakeLog, stdout: rows)
        ])
        let report = await collector(runner).collect(now: now)
        let focused = try #require(report.focusedWake)
        let bluetooth = report.events.filter { $0.bluetoothEvent != nil }
        #expect(bluetooth.count == 3)
        #expect(Set(bluetooth.map(\.id)).count == 3)
        #expect(Set(focused.events.map(\.id)) == Set(bluetooth.map(\.id)))
        #expect(bluetooth.filter { $0.severity == .error }.count == 2)
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        #expect(!json.contains("PRIVATE-ONE"))
        #expect(!json.contains("PRIVATE-TWO"))
    }

    @Test func focusedEvidenceSurvivesGlobalOverflowAndReservesLifecycleWhenLocallyCapped() async throws {
        var rows = try [
            record("2026-10-17T10:59:59Z", "HCI command failure", type: "Error", process: "bluetoothd"),
            record("2026-10-17T11:00:00Z", "[system/com.apple.bluetoothd:] exited", process: "launchd"),
            record("2026-10-17T11:00:01Z", "[system/com.apple.bluetoothd:] spawned with pid 42", process: "launchd")
        ]
        rows += try (0..<600).map { index in
            try record(String(format: "2026-10-17T11:00:02.%03dZ", index), "HCI command failure", type: "Error", process: "bluetoothd")
        }
        let history = try (0..<600).map { index in
            try record(String(format: "2026-10-17T11:30:00.%03dZ", index), "Wake transition failed", type: "Error")
        }.joined(separator: "\n")
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeIncidentLog: .init(command: .wakeIncidentLog, stdout: rows.joined(separator: "\n")),
            .sleepWakeLog: .init(command: .sleepWakeLog, stdout: history)
        ])
        let report = await collector(runner).collect(now: now)
        let focus = try #require(report.focusedWake)
        #expect(focus.events.count == 500)
        #expect(focus.omittedEventCount == 103)
        #expect(focus.coverage.state == .available)
        #expect(focus.scanSummary?.matchedEventCount == 603)
        #expect(focus.events.contains { $0.timestamp == LogTimestamp.parse("2026-10-17T10:59:59Z") && $0.bluetoothEvent == .hciFailure })
        #expect(focus.events.contains { $0.bluetoothEvent == .daemonExit })
        #expect(focus.events.contains { $0.bluetoothEvent == .daemonStart })
        #expect(report.events.count == 500)
        #expect(report.events.contains { $0.bluetoothEvent == .daemonExit })
        #expect(report.events.contains { $0.bluetoothEvent == .daemonStart })
        #expect(report.hasIncompleteCoverage)
    }

    @Test func focusedTimeoutAndMalformedOutputRemainExplicitlyIncomplete() async throws {
        let row = try record("2026-10-17T11:00:01Z", "HCI command failure", type: "Error", process: "bluetoothd")
        let partialRunner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeIncidentLog: .init(command: .wakeIncidentLog, stdout: row + "\n{truncated", exitCode: nil, termination: .timedOut, outputWasTruncated: true)
        ])
        let partial = await collector(partialRunner).collect(now: now)
        #expect(partial.focusedWake?.coverage.state == .partial)
        #expect(partial.focusedWake?.events.count == 1)
        #expect(partial.hasIncompleteCoverage)
        let unavailableRunner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeIncidentLog: .init(command: .wakeIncidentLog, stderr: "PRIVATE-STDERR", exitCode: nil, termination: .timedOut),
            .wakeBluetoothLog: .init(command: .wakeBluetoothLog, exitCode: nil, termination: .timedOut),
            .wakeBluetoothLifecycleLog: .init(command: .wakeBluetoothLifecycleLog, exitCode: nil, termination: .timedOut)
        ])
        let unavailable = await collector(unavailableRunner).collect(now: now)
        #expect(unavailable.focusedWake?.coverage.state == .unavailable)
        #expect(unavailable.focusedWake?.events.isEmpty == true)
        #expect(unavailable.hasIncompleteCoverage)
        #expect(unavailable.section.item("sleepWakeErrors")?.status == .unknown)
        #expect(!String(decoding: try JSONEncoder().encode(unavailable), as: UTF8.self).contains("PRIVATE-STDERR"))
    }

    @Test func separateHCIFloodPreservesOtherErrorCategoriesAndLifecycleInBothViews() async throws {
        let incidentRows = try [
            record("2026-10-17T10:59:58Z", "AppleUSBIORequest iSight transfer stalled", type: "Error", process: "kernel"),
            record("2026-10-17T10:59:58.100Z", "AppleUSBHostUserClient USB exclusive access denied for Display Audio", type: "Error", process: "kernel"),
            record("2026-10-17T10:59:58.200Z", "[987654] is not entitled to set wake reason", type: "Error", process: "kernel"),
            record("2026-10-17T10:59:58.300Z", "Wake transition timed out", type: "Error"),
            record("2026-10-17T10:59:58.400Z", "GPU command failed", type: "Error", process: "kernel"),
            record("2026-10-17T11:00:00Z", "[system/com.apple.bluetoothd:] exited", process: "launchd"),
            record("2026-10-17T11:00:01Z", "[system/com.apple.bluetoothd:] spawned with pid 42", process: "launchd")
        ].joined(separator: "\n")
        let hciRows = try (0..<600).map { index in
            try record(String(format: "2026-10-17T11:00:02.%03dZ", index), "HCI command failure", type: "Error", process: "bluetoothd")
        }.joined(separator: "\n")
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeIncidentLog: .init(command: .wakeIncidentLog, stdout: incidentRows),
            .wakeBluetoothLog: .init(command: .wakeBluetoothLog, stdout: hciRows)
        ])
        let report = await collector(runner).collect(now: now)
        let focus = try #require(report.focusedWake)
        #expect(focus.events.count == 500)
        #expect(focus.omittedEventCount == 107)
        #expect(focus.coverage.state == .available)
        #expect(focus.coverage.evidence.count == 5)
        #expect(focus.scanSummary?.matchedEventCount == 607)
        #expect(focus.bluetoothSummary.hciFailureCount == 600)
        #expect(report.events.count == 500)
        for events in [focus.events, report.events] {
            #expect(events.contains { $0.bluetoothEvent == .daemonExit })
            #expect(events.contains { $0.bluetoothEvent == .daemonStart })
            for category in [SleepWakeErrorCategory.isightTransfer, .usbExclusiveAccess, .wakePermission, .transitionFailure, .graphics, .bluetoothHCI] {
                #expect(events.contains { $0.errorCategory == category })
            }
            #expect(events.filter { $0.severity == .error && $0.bluetoothEvent != .hciFailure }.count == 5)
        }
    }

    @Test func oneFocusedQueryCannotConcealTheOtherQueryTimeout() async throws {
        let lifecycle = try record("2026-10-17T11:00:01Z", "[system/com.apple.bluetoothd:] exited", process: "launchd")
        let failure = try record("2026-10-17T11:00:00Z", "HCI command failure", type: "Error", process: "bluetoothd")
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeIncidentLog: .init(command: .wakeIncidentLog, stdout: lifecycle),
            .wakeBluetoothLog: .init(command: .wakeBluetoothLog, stdout: failure, exitCode: nil, termination: .timedOut, outputWasTruncated: true)
        ])
        let report = await collector(runner).collect(now: now)
        let focus = try #require(report.focusedWake)
        #expect(focus.coverage.state == .partial)
        #expect(focus.segments?.first { $0.id == "wake-incident" }?.coverage.state == .available)
        #expect(focus.segments?.filter { $0.id.hasPrefix("wake-hci-") }.allSatisfy { $0.coverage.state == .partial } == true)
        #expect(focus.coverage.evidence.count == 5)
        #expect(focus.events.count == 2)
        #expect(focus.events.contains { $0.bluetoothEvent == .daemonExit })
        #expect(focus.events.contains { $0.bluetoothEvent == .hciFailure })
        #expect(report.hasIncompleteCoverage)

        let reverseRunner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeIncidentLog: .init(command: .wakeIncidentLog, exitCode: nil, termination: .timedOut),
            .wakeBluetoothLog: .init(command: .wakeBluetoothLog, stdout: failure)
        ])
        let reverse = await collector(reverseRunner).collect(now: now)
        #expect(reverse.focusedWake?.coverage.state == .partial)
        #expect(reverse.focusedWake?.segments?.first { $0.id == "wake-incident" }?.coverage.state == .unavailable)
        #expect(reverse.focusedWake?.segments?.filter { $0.id.hasPrefix("wake-hci-") }.allSatisfy { $0.coverage.state == .available } == true)
        #expect(reverse.focusedWake?.events.first?.bluetoothEvent == .hciFailure)
    }

    @Test func compactFloodCountsEveryRowWhileKeepingOnlyBoundedSamples() async throws {
        let row = "2026-10-17 11:00:01.123 E bluetoothd[987654321:abc] [com.apple.bluetooth:HCI] HCI command failure PRIVATE-DEVICE"
        let output = "Timestamp Ty Process[PID:TID]\n" + Array(repeating: row, count: 1_200).joined(separator: "\n")
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeBluetoothLog: .init(command: .wakeBluetoothLog, stdout: output)
        ])
        let report = await collector(runner).collect(now: now)
        let focus = try #require(report.focusedWake)
        #expect(focus.coverage.state == .available)
        #expect(focus.matchedEventCount == 1_200)
        #expect(focus.scanSummary?.errorCount == 1_200)
        #expect(focus.bluetoothSummary.hciFailureCount == 1_200)
        #expect(focus.events.count == 500)
        #expect(focus.omittedEventCount == 700)
        #expect(Set(focus.events.map(\.id)).count == 500)
        #expect(!focus.hasIncompleteCoverage)
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        #expect(!json.contains("987654321"))
        #expect(!json.contains("PRIVATE-DEVICE"))
    }

    @Test func fractionalCollectionTimeAndWakeProduceIntegralQueryBoundaries() async throws {
        let fractionalNow = now.addingTimeInterval(0.75)
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: "2026-10-17 11:59:30.125 +0000 Wake                 Wake from Normal Sleep")
        ])
        let report = await collector(runner).collect(now: fractionalNow)
        let focus = try #require(report.focusedWake)
        #expect(focus.wakeAt == LogTimestamp.parse("2026-10-17T11:59:30.125Z"))
        #expect(focus.start == LogTimestamp.parse("2026-10-17T11:54:31Z"))
        #expect(focus.end == now)
        let windows = await runner.windows
        #expect(windows.allSatisfy {
            $0.0.timeIntervalSince1970.rounded(.down) == $0.0.timeIntervalSince1970
                && $0.1.timeIntervalSince1970.rounded(.down) == $0.1.timeIntervalSince1970
                && $0.0 < $0.1 && $0.1 <= fractionalNow
        })
    }

    @Test func compactSlicesAreReadLateFirstAndUseHalfOpenBoundaries() async throws {
        let rows = ["10:59:59.999", "11:00:00.000", "11:00:10.000", "11:02:00.000"].map {
            "2026-10-17 \($0) E bluetoothd[5:abc] HCI command failure"
        }.joined(separator: "\n")
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeBluetoothLog: .init(command: .wakeBluetoothLog, stdout: rows)
        ])
        let report = await collector(runner).collect(now: now)
        let focus = try #require(report.focusedWake)
        #expect(focus.matchedEventCount == 4)
        #expect(focus.bluetoothSummary.hciFailureCount == 4)
        #expect(focus.events.count == 4)
        let windows = await runner.hciWindows
        #expect(windows.map { $0.0 } == [LogTimestamp.parse("2026-10-17T11:00:10Z")!, focus.start, focus.wakeAt])
        #expect(windows.map { $0.1 } == [focus.end, focus.wakeAt, LogTimestamp.parse("2026-10-17T11:00:10Z")!])
        #expect(focus.segments?.count == 5)
    }

    @Test func completedPostBurstEvidenceSurvivesAnIndependentBurstTimeout() async throws {
        let late = "2026-10-17 11:00:52.673 E bluetoothd[3:abc] HCI command failed"
        let runner = BluetoothRunner(outputs: [.powerHistory: .init(command: .powerHistory, stdout: wake)],
            hciOverrides: [
                LogTimestamp.parse("2026-10-17T11:00:10Z")!: .init(command: .wakeBluetoothLog, stdout: late),
                LogTimestamp.parse("2026-10-17T11:00:00Z")!: .init(command: .wakeBluetoothLog, exitCode: nil, termination: .timedOut)
            ])
        let report = await collector(runner).collect(now: now)
        let focus = try #require(report.focusedWake)
        #expect(focus.coverage.state == .partial)
        #expect(focus.segments?.first { $0.id == "wake-hci-after" }?.coverage.state == .available)
        #expect(focus.segments?.first { $0.id == "wake-hci-initial" }?.coverage.state == .unavailable)
        #expect(focus.bluetoothSummary.hciFailureCount == 1)
        let observed = try #require(focus.events.first?.timestamp)
        #expect(abs(observed.timeIntervalSince(LogTimestamp.parse("2026-10-17T11:00:52.673Z")!)) < 0.000_001)
        #expect(focus.hasIncompleteCoverage)
    }

    @Test func distinctProcessRangesProducePrivateInferenceButWiproxIsNotBluetoothStartup() async throws {
        let rows = [
            "2026-10-17 11:00:01.000 E bluetoothd[987654321:abc] HCI command failure",
            "2026-10-17 11:00:52.673 E bluetoothd[876543219:abc] HCI command failed"
        ].joined(separator: "\n")
        let wiprox = try record("2026-10-17T11:00:52.188Z", "STARTED WIPROX DAEMON", process: "bluetoothd")
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeBluetoothLog: .init(command: .wakeBluetoothLog, stdout: rows),
            .wakeBluetoothLifecycleLog: .init(command: .wakeBluetoothLifecycleLog, stdout: wiprox)
        ])
        let report = await collector(runner).collect(now: now)
        let focus = try #require(report.focusedWake)
        let changes = focus.events.filter { $0.bluetoothEvent == .daemonInstanceChange }
        #expect(changes.count == 1)
        #expect(changes.first?.detail.contains("Exact exit/start time and cause are not established") == true)
        #expect(!focus.events.contains { $0.bluetoothEvent == .daemonStart || $0.bluetoothEvent == .daemonExit })
        #expect(focus.bluetoothSummary.hciFailureCount == 2)
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        #expect(!json.contains("987654321"))
        #expect(!json.contains("876543219"))
        #expect(!json.contains("WIPROX"))
    }

    @Test func overlappingProcessRangesDoNotEstablishAnInstanceChangeAndOverflowIsPartial() async throws {
        let overlapping = [
            "2026-10-17 11:00:01.000 E bluetoothd[1:abc] HCI command failure",
            "2026-10-17 11:00:02.000 E bluetoothd[2:abc] HCI command failure",
            "2026-10-17 11:00:03.000 E bluetoothd[3:abc] HCI command failure",
            "2026-10-17 11:00:04.000 E bluetoothd[1:abc] HCI command failure"
        ].joined(separator: "\n")
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeBluetoothLog: .init(command: .wakeBluetoothLog, stdout: overlapping)
        ])
        let report = await collector(runner).collect(now: now)
        #expect(!report.events.contains { $0.bluetoothEvent == .daemonInstanceChange })
        let overflow = (1...65).map { "2026-10-17 11:00:01.000 E bluetoothd[\($0):abc] HCI command failure" }.joined(separator: "\n")
        let overflowRunner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeBluetoothLog: .init(command: .wakeBluetoothLog, stdout: overflow)
        ])
        let limited = await collector(overflowRunner).collect(now: now)
        #expect(limited.focusedWake?.coverage.state == .partial)
        #expect(limited.focusedWake?.bluetoothSummary.hciFailureCount == 65)
        #expect(limited.focusedWake?.coverage.detail.contains("process-identity tracking limit") == true)
    }

    private func collect(focused: String) async -> SleepWakeReport {
        let runner = BluetoothRunner(outputs: [
            .powerHistory: .init(command: .powerHistory, stdout: wake),
            .wakeIncidentLog: .init(command: .wakeIncidentLog, stdout: focused)
        ])
        return await collector(runner).collect(now: now)
    }

    private func collector(_ runner: BluetoothRunner) -> SleepWakeCollector {
        SleepWakeCollector(runner: runner, reportCollector: DiagnosticReportCollector(reader: BluetoothReportReader()))
    }

    private func record(_ timestamp: String, _ message: String, type: String = "Default", process: String = "powerd") throws -> String {
        let object = ["timestamp": timestamp, "eventMessage": message, "messageType": type, "processImagePath": "/usr/sbin/" + process]
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
}

private actor BluetoothRunner: CommandExecuting {
    let outputs: [DiagnosticCommand: CommandOutput]
    let hciOverrides: [Date: CommandOutput]
    private(set) var calls = [DiagnosticCommand]()
    private(set) var windows = [(Date, Date)]()
    private(set) var hciWindows = [(Date, Date)]()
    init(outputs: [DiagnosticCommand: CommandOutput], hciOverrides: [Date: CommandOutput] = [:]) {
        self.outputs = outputs; self.hciOverrides = hciOverrides
    }
    func run(_ command: DiagnosticCommand) async -> CommandOutput {
        calls.append(command)
        return outputs[command] ?? CommandOutput(command: command)
    }
    func runWakeIncidentLog(since: Date, until: Date) async -> CommandOutput {
        windowOutput(.wakeIncidentLog, since: since, until: until)
    }
    func runWakeBluetoothLog(since: Date, until: Date) async -> CommandOutput {
        windowOutput(.wakeBluetoothLog, since: since, until: until)
    }
    func runWakeBluetoothLifecycleLog(since: Date, until: Date) async -> CommandOutput {
        windowOutput(.wakeBluetoothLifecycleLog, since: since, until: until)
    }
    private func windowOutput(_ command: DiagnosticCommand, since: Date, until: Date) -> CommandOutput {
        calls.append(command)
        windows.append((since, until))
        if command == .wakeBluetoothLog { hciWindows.append((since, until)) }
        let output = (command == .wakeBluetoothLog ? hciOverrides[since] : nil) ?? outputs[command] ?? CommandOutput(command: command)
        return CommandOutput(command: command, stdout: output.stdout, stderr: output.stderr,
            exitCode: output.exitCode, termination: output.termination, outputWasTruncated: output.outputWasTruncated,
            windowStart: since, windowEnd: until)
    }
}

private struct BluetoothReportReader: DiagnosticReportReading {
    func read(since: Date, until: Date) -> DiagnosticReportReadBatch { .init() }
}
