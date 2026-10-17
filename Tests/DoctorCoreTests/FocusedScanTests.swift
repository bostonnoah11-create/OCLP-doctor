import Foundation
import Testing
@testable import DoctorCore

@Suite
struct FocusedScanTests {
    private let wake = Date(timeIntervalSince1970: 1_792_241_118)
    private var start: Date { wake.addingTimeInterval(-300) }
    private var end: Date { wake.addingTimeInterval(120) }

    private func coverage(_ state: LogCoverageState = .available) -> LogSourceCoverage {
        LogSourceCoverage(id: "focused-fixture", name: "Synthetic focused query", state: state,
            detail: "Synthetic bounded query evidence", evidence: [])
    }
    private func event(_ id: String, _ offset: TimeInterval, _ bluetooth: BluetoothEventKind? = nil,
                       severity: LogSeverity = .information) -> SleepWakeEvent {
        SleepWakeEvent(id: id, timestamp: wake.addingTimeInterval(offset), kind: .relatedRecord,
            severity: severity, title: "Synthetic record", detail: "Synthetic privacy-safe evidence",
            source: "Synthetic source", evidence: [], bluetoothEvent: bluetooth)
    }
    private func summary(_ events: [SleepWakeEvent], state: LogCoverageState = .available) -> FocusedWakeScanSummary {
        FocusedWakeScanSummary(events: events, start: start, end: end, coverage: coverage(state))
    }
    private func focus(_ all: [SleepWakeEvent], samples: [SleepWakeEvent]? = nil,
                       state: LogCoverageState = .available, segments: [FocusedLogSegment]? = nil) -> FocusedWakeEvidence {
        FocusedWakeEvidence(wakeAt: wake, start: start, end: end, events: samples ?? all,
            coverage: coverage(state), scanSummary: summary(all, state: state), segments: segments)
    }
    private var restart: [SleepWakeEvent] {
        [event("hci", 1, .hciFailure), event("exit", 2, .daemonExit),
         event("start", 3, .daemonStart), event("ready", 4, .controllerReady)]
    }

    @Test func fullCountsDeduplicateIDsFilterWindowAndSeparateSourceSeverity() {
        let first = event("first", -300, .hciFailure, severity: .error)
        let info = event("info-hci", 0, .hciFailure)
        let fault = event("fault", 0, severity: .fault)
        let warning = event("warning", 2, severity: .warning)
        let last = event("last", 120, severity: .error)
        let scan = summary([last, first, info, fault, warning, first, last,
                            event("before", -301, .hciFailure), event("after", 121, .hciFailure)])
        #expect(scan.matchedEventCount == 5)
        #expect(scan.errorCount == 2 && scan.faultCount == 1 && scan.warningCount == 1)
        #expect(scan.errorGroups.reduce(0) { $0 + $1.count } == scan.errorCount)
        #expect(scan.errorGroups.first { $0.category == .bluetoothHCI }?.count == 1)
        #expect(scan.bluetoothSummary.hciFailureCount == 2)
        #expect(scan.bluetoothSummary.firstHCIFailureAt == start)
        #expect(scan.bluetoothSummary.lastHCIFailureAt == wake)
    }

    @Test func interiorFailureAbsentFromDisplayStillCountsAfterRestart() {
        let initial = (0..<600).map { event("hci-\($0)", -280 + Double($0) / 10, .hciFailure, severity: .error) }
        let lifecycle = [event("exit", 1, .daemonExit), event("start", 2, .daemonStart), event("ready", 3, .controllerReady)]
        let middle = event("middle-recurrence", 20, .hciFailure, severity: .error)
        let last = event("last-recurrence", 30, .hciFailure, severity: .error)
        let result = focus(initial + lifecycle + [middle, last], samples: Array(initial.prefix(500)))
        #expect(result.matchedEventCount == 605)
        #expect(result.displayedEventCount == 500 && result.omittedEventCount == 105)
        #expect(!result.hasIncompleteCoverage)
        #expect(result.errorGroups.reduce(0) { $0 + $1.count } == 602)
        #expect(result.bluetoothSummary.hciFailureCount == 602)
        #expect(result.bluetoothSummary.subsequentFailureCount == 2)
        #expect(!result.bluetoothSummary.sequence.contains { $0.id == middle.id })
        #expect(!result.bluetoothSummary.detail.contains("No further HCI"))
        #expect(result.bluetoothSummary.sequenceOmittedEventCount == 600)
    }

    @Test func completedScanCanDescribeBoundedAbsenceDespiteDisplaySampling() {
        let faults = (0..<600).map { event("fault-\($0)", -290 + Double($0) / 10, severity: .fault) }
        let result = focus(faults + restart, samples: Array(faults.prefix(500)))
        #expect(result.omittedEventCount == 104 && !result.hasIncompleteCoverage)
        #expect(result.bluetoothSummary.countsAreFromFullScan)
        #expect(result.bluetoothSummary.subsequentFailureCount == 0)
        #expect(result.bluetoothSummary.detail.contains("No further HCI failure signature"))
        #expect(result.bluetoothSummary.detail.contains(LogTimestamp.display(end, fractionalSeconds: true)))
        #expect(result.bluetoothSummary.detail.contains("does not prove"))
    }

    @Test func partialSummaryOuterCoverageOrSegmentCannotSupportAbsence() {
        let completeSummary = summary(restart)
        for state in [LogCoverageState.partial, .unavailable] {
            let partial = focus(restart, state: state)
            let outer = FocusedWakeEvidence(wakeAt: wake, start: start, end: end, events: restart,
                coverage: coverage(state), scanSummary: completeSummary)
            let segment = FocusedLogSegment(id: "hci-segment", kind: "Bluetooth HCI", start: start, end: end,
                coverage: coverage(state))
            let segmented = focus(restart, segments: [segment])
            for result in [partial, outer, segmented] {
                #expect(result.hasIncompleteCoverage)
                #expect(!result.bluetoothSummary.hasCompleteCoverage)
                #expect(!result.bluetoothSummary.detail.contains("No further HCI"))
                #expect(result.bluetoothSummary.detail.contains("cannot establish no recurrence"))
                #expect(result.bluetoothSummary.hciFailureCount == 1)
            }
        }
    }

    @Test func latestStrictlyOrderedRestartDefinesItsOwnRecurrenceWindow() {
        let events = [event("hci-1", -20, .hciFailure), event("exit-1", -18, .daemonExit),
            event("start-1", -17, .daemonStart), event("ready-1", -16, .controllerReady),
            event("hci-2", -10, .hciFailure), event("exit-2", -8, .daemonExit),
            event("start-2", -7, .daemonStart), event("ready-2", -6, .controllerReady)]
        let result = summary(events).bluetoothSummary
        #expect(result.hciFailureCount == 2)
        #expect(result.recurrenceStart == wake.addingTimeInterval(-7))
        #expect(result.recurrenceEnd == end && result.subsequentFailureCount == 0)
        #expect(result.detail.contains(LogTimestamp.display(wake.addingTimeInterval(-7), fractionalSeconds: true)))
        #expect(result.title.contains("controller-ready"))
    }

    @Test func recurrenceIntervalStopsAtTheNextRecordedExit() {
        let result = summary(restart + [event("next-exit", 8, .daemonExit), event("later-hci", 9, .hciFailure)]).bluetoothSummary
        #expect(result.hciFailureCount == 2)
        #expect(result.recurrenceEnd == wake.addingTimeInterval(8))
        #expect(result.subsequentFailureCount == 0)
        #expect(result.lastHCIFailureAt == wake.addingTimeInterval(9))
        #expect(result.detail.contains("next recorded exit"))
    }

    @Test func equalTimestampsDoNotEstablishFailureOrLifecycleOrdering() {
        let failure = summary(restart + [event("same-time-hci", 3, .hciFailure)]).bluetoothSummary
        #expect(failure.subsequentFailureCount == 1 && failure.sameTimestampFailureCount == 1)
        #expect(!failure.detail.contains("No further HCI"))
        let lifecycle = summary([event("hci", 1, .hciFailure), event("exit", 2, .daemonExit),
                                 event("start", 2, .daemonStart), event("ready", 2, .controllerReady)]).bluetoothSummary
        #expect(lifecycle.title.contains("ordering is unverified"))
        #expect(!lifecycle.title.contains("controller-ready"))
    }

    @Test func noStartOrZeroLengthObservationCannotSupportNoRecurrence() {
        let noStart = summary([event("hci", 1, .hciFailure), event("ready", 2, .controllerReady)]).bluetoothSummary
        #expect(noStart.recurrenceStart == nil && noStart.subsequentFailureCount == nil)
        #expect(!noStart.detail.contains("No further HCI"))
        let atEnd = summary([event("hci", 1, .hciFailure), event("exit", 2, .daemonExit),
                             event("start", 120, .daemonStart)]).bluetoothSummary
        #expect(atEnd.recurrenceStart == atEnd.recurrenceEnd)
        #expect(!atEnd.detail.contains("No further HCI"))
        #expect(atEnd.detail.contains("no positive observation interval"))
    }

    @Test func bluetoothSequenceIsBoundedWithoutChangingCounts() {
        let lifecycle = (0..<150).map { event("start-\($0)", -100 + Double($0), .daemonStart) }
        let events = [event("first-hci", -200, .hciFailure)] + lifecycle + [event("last-hci", 60, .hciFailure)]
        let result = summary(events).bluetoothSummary
        #expect(result.sequence.count == 100 && result.sequenceOmittedEventCount == 52)
        #expect(result.sequence.first?.id == "first-hci" && result.sequence.last?.id == "last-hci")
        #expect(result.sequence.contains { $0.id == "start-149" })
        #expect(result.hciFailureCount == 2 && result.subsequentFailureCount == 1)
        #expect(result.detail.contains("included in the counts above"))
    }

    @Test func unavailableEmptyScanDoesNotBecomeNoFailureVerdict() {
        let result = focus([], state: .unavailable)
        #expect(result.matchedEventCount == 0 && result.hasIncompleteCoverage)
        #expect(!result.bluetoothSummary.hasCompleteCoverage)
        #expect(result.bluetoothSummary.subsequentFailureCount == nil)
        #expect(result.bluetoothSummary.detail.contains("cannot establish no recurrence"))
    }

    @Test func compactObservationsPreserveRowsWithIdenticalMillisecondTimestamps() {
        let repeated = BluetoothFailureObservation(timestamp: wake.addingTimeInterval(3), severity: .error)
        let observations = [BluetoothFailureObservation(timestamp: wake.addingTimeInterval(1), severity: .information),
                            repeated, repeated, repeated,
                            BluetoothFailureObservation(timestamp: wake.addingTimeInterval(121), severity: .error)]
        let scan = FocusedWakeScanSummary(events: restart, start: start, end: end, coverage: coverage(),
            hciObservations: observations)
        #expect(scan.matchedEventCount == 7)
        #expect(scan.errorCount == 3)
        #expect(scan.errorGroups.first { $0.category == .bluetoothHCI }?.count == 3)
        #expect(scan.bluetoothSummary.hciFailureCount == 4)
        #expect(scan.bluetoothSummary.subsequentFailureCount == 3)
        #expect(scan.bluetoothSummary.sameTimestampFailureCount == 3)
        #expect(!scan.bluetoothSummary.detail.contains("No further HCI"))
    }

    @Test func denseCompactBurstAggregatesWithoutSerializingEveryObservation() throws {
        let repeated = BluetoothFailureObservation(timestamp: wake, severity: .error)
        let observations = Array(repeating: repeated, count: 155_192)
        let scan = FocusedWakeScanSummary(events: [], start: start, end: end, coverage: coverage(),
            hciObservations: observations)
        #expect(scan.matchedEventCount == 155_192 && scan.errorCount == 155_192)
        #expect(scan.errorGroups.reduce(0) { $0 + $1.count } == 155_192)
        #expect(scan.bluetoothSummary.hciFailureCount == 155_192)
        #expect(scan.bluetoothSummary.sequence.count == 2)
        #expect(scan.bluetoothSummary.sequenceOmittedEventCount == 155_190)
        #expect(scan.bluetoothSummary.sequence.allSatisfy { $0.timestamp == wake && $0.severity == .error })
        let encoded = try JSONEncoder().encode(scan)
        #expect(encoded.count < 20_000)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("hciObservations"))
    }

    @Test func compactMillisecondBucketCannotHideFailureAfterMicrosecondStart() {
        let lifecycle = [event("exit", 2, .daemonExit), event("start", 3.0004, .daemonStart)]
        let observations = [BluetoothFailureObservation(timestamp: wake.addingTimeInterval(1), severity: .error),
                            BluetoothFailureObservation(timestamp: wake.addingTimeInterval(3), severity: .error)]
        let scan = FocusedWakeScanSummary(events: lifecycle, start: start, end: end, coverage: coverage(),
            hciObservations: observations)
        #expect(scan.bluetoothSummary.subsequentFailureCount == 1)
        #expect(scan.bluetoothSummary.sameTimestampFailureCount == 1)
        #expect(!scan.bluetoothSummary.detail.contains("No further HCI"))
        #expect(scan.bluetoothSummary.detail.contains("millisecond precision"))
    }

    @Test func authoritativeEmptyCompactInputDoesNotCountHCISampleTwice() {
        let scan = FocusedWakeScanSummary(events: restart, start: start, end: end, coverage: coverage(),
            hciObservations: [])
        #expect(scan.matchedEventCount == 3 && scan.errorCount == 0)
        #expect(scan.bluetoothSummary.hciFailureCount == 0)
        #expect(scan.bluetoothSummary.sequence.allSatisfy { $0.bluetoothEvent != .hciFailure })
    }

    @Test func differentDaemonInstanceWithSameTimeFailureDoesNotConfirmRestartOrRecovery() {
        let events = [event("first-hci", 1, .hciFailure), event("instance-change", 2, .daemonInstanceChange),
                      event("later-hci", 2, .hciFailure)]
        let result = summary(events).bluetoothSummary
        #expect(result.title == "Later HCI failure came from a different Bluetooth daemon process")
        #expect(result.hciFailureCount == 2)
        #expect(result.recurrenceStart == nil && result.subsequentFailureCount == nil)
        #expect(result.detail.contains("consistent with a restart"))
        #expect(result.detail.contains("exact start, exit and cause are unverified"))
        #expect(!result.detail.contains("No further HCI"))
        #expect(result.sequence.contains { $0.id == "instance-change" })
    }

    @Test func instanceChangeWithoutLaterFailureStillCannotEstablishAbsence() {
        let lifecycle = (0..<130).map { event("ready-\($0)", 3 + Double($0) / 10, .controllerReady) }
        let events = [event("first-hci", 1, .hciFailure), event("instance-change", 2, .daemonInstanceChange)] + lifecycle
        let result = focus(events, state: .partial).bluetoothSummary
        #expect(result.title == "Different Bluetooth daemon processes were observed")
        #expect(result.recurrenceStart == nil && result.subsequentFailureCount == nil)
        #expect(!result.detail.contains("No further HCI"))
        #expect(result.detail.contains("not an explicit daemon-start record"))
        #expect(result.sequence.count == 100)
        #expect(result.sequence.contains { $0.id == "instance-change" })
    }

    @Test func derivedInstanceAnnotationDoesNotInflateSourceCountsOrInvalidateSummary() {
        let raw = [event("first-hci", 1, .hciFailure, severity: .error),
                   event("later-hci", 2, .hciFailure, severity: .error)]
        // Even a malformed annotation's level cannot manufacture a source Error record.
        let annotation = event("instance-change", 2, .daemonInstanceChange, severity: .error)
        let result = focus(raw + [annotation])
        #expect(result.matchedEventCount == 2)
        #expect(result.displayedEventCount == 3 && result.derivedEventCount == 1)
        #expect(result.sourceSampleEventCount == 2 && result.omittedEventCount == 0)
        #expect(result.scanSummary?.errorCount == 2)
        #expect(result.errorGroups.reduce(0) { $0 + $1.count } == 2)
        #expect(result.bluetoothSummary.countsAreFromFullScan && !result.hasIncompleteCoverage)
        #expect(result.bluetoothSummary.sequence.contains { $0.id == annotation.id })
    }

    @Test func compactCountsAndDisplayOmissionsExcludeDerivedAnnotations() {
        let raw = [event("first-hci", 1, .hciFailure), event("later-hci", 2, .hciFailure)]
        let annotation = event("instance-change", 2, .daemonInstanceChange)
        let observations = [BluetoothFailureObservation(timestamp: wake.addingTimeInterval(1), severity: .information),
                            BluetoothFailureObservation(timestamp: wake.addingTimeInterval(2), severity: .information),
                            BluetoothFailureObservation(timestamp: wake.addingTimeInterval(2), severity: .information)]
        let scan = FocusedWakeScanSummary(events: raw + [annotation], start: start, end: end,
            coverage: coverage(), hciObservations: observations)
        let result = FocusedWakeEvidence(wakeAt: wake, start: start, end: end, events: raw + [annotation],
            coverage: coverage(), scanSummary: scan)
        #expect(result.matchedEventCount == 3 && result.displayedEventCount == 3)
        #expect(result.sourceSampleEventCount == 2 && result.derivedEventCount == 1)
        #expect(result.omittedEventCount == 1)
        #expect(result.bluetoothSummary.hciFailureCount == 3 && result.bluetoothSummary.countsAreFromFullScan)
    }

    @Test func oldSnapshotsRemainConservativeAndNewSummariesRoundTrip() throws {
        let segment = FocusedLogSegment(id: "segment", kind: "Bluetooth HCI", start: start, end: end, coverage: coverage())
        let original = focus(restart, samples: Array(restart.prefix(1)), segments: [segment])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FocusedWakeEvidence.self, from: data)
        #expect(decoded.scanSummary?.matchedEventCount == 4 && decoded.omittedEventCount == 3)
        #expect(decoded.segments?.first?.kind == "Bluetooth HCI")
        #expect(decoded.bluetoothSummary.subsequentFailureCount == 0 && !decoded.hasIncompleteCoverage)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "scanSummary")
        legacy.removeValue(forKey: "segments")
        let old = try JSONDecoder().decode(FocusedWakeEvidence.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.scanSummary == nil && old.hasIncompleteCoverage)
        #expect(!old.bluetoothSummary.countsAreFromFullScan)
        #expect(!old.bluetoothSummary.detail.contains("No further HCI"))
    }

    @Test func mismatchedSummaryWindowCannotSupplyTrustedCountsOrAbsence() {
        let foreign = FocusedWakeScanSummary(events: restart, start: start.addingTimeInterval(-1), end: end, coverage: coverage())
        let result = FocusedWakeEvidence(wakeAt: wake, start: start, end: end, events: restart,
            coverage: coverage(), scanSummary: foreign)
        #expect(result.hasIncompleteCoverage)
        #expect(!result.bluetoothSummary.countsAreFromFullScan)
        #expect(!result.bluetoothSummary.detail.contains("No further HCI"))
    }
}
