import Foundation
import Testing
@testable import DoctorCore

@Suite
struct WakeIncidentTests {
    private let wake = Date(timeIntervalSince1970: 1_792_241_118)

    private func event(_ id: String, offset: TimeInterval = 1, detail: String = "Synthetic evidence",
                       severity: LogSeverity = .error, bluetooth: BluetoothEventKind? = nil) -> SleepWakeEvent {
        SleepWakeEvent(id: id, timestamp: wake.addingTimeInterval(offset), kind: bluetooth == .hciFailure ? .relatedError : .relatedRecord,
            severity: severity, title: "Synthetic record", detail: detail, source: "Fixture", evidence: [], bluetoothEvent: bluetooth)
    }
    private func focused(_ events: [SleepWakeEvent], state: LogCoverageState = .available, omitted: Int = 0) -> FocusedWakeEvidence {
        FocusedWakeEvidence(wakeAt: wake, start: wake.addingTimeInterval(-300), end: wake.addingTimeInterval(120), events: events,
            coverage: LogSourceCoverage(id: "focus", name: "Fixture", state: state, detail: "Synthetic query", evidence: []), omittedEventCount: omitted)
    }
    private func sequence() -> [SleepWakeEvent] {
        [event("hci", offset: 3, severity: .information, bluetooth: .hciFailure),
         event("exit", offset: 4, severity: .information, bluetooth: .daemonExit),
         event("start", offset: 5, severity: .information, bluetooth: .daemonStart),
         event("ready", offset: 6, severity: .information, bluetooth: .controllerReady)]
    }

    @Test func synthetic105RecordsSplitByMeaningNotIncidents() {
        let events = (0..<65).map { event("permission-\($0)", detail: "process is not entitled to set wake reason") }
            + (0..<26).map { event("exclusive-\($0)", detail: "AppleUSBHostUserClient failed to open Display iSight: already opened for exclusive access") }
            + (0..<14).map { event("stall-\($0)", detail: "Display iSight USB pipe stalled, status 0xe0005000") }
        let groups = SleepWakeReport.groupErrors(events)
        #expect(groups.reduce(0) { $0 + $1.count } == 105)
        #expect(groups.first { $0.category == .wakePermission }?.count == 65)
        #expect(groups.first { $0.category == .usbExclusiveAccess }?.count == 26)
        #expect(groups.first { $0.category == .isightTransfer }?.count == 14)
    }

    @Test func observedExclusiveOpenedWordingIsNotClassifiedAsOther() {
        for wording in ["provider exclusively opened", "provider is exclusively open", "provider is already opened for exclusive access"] {
            #expect(event("usb", detail: "AppleUSBHostUserClient::openGated failed: \(wording)").errorCategory == .usbExclusiveAccess)
        }
    }

    @Test func unknownErrorsAreNotDiscardedAndFaultTracesAreNotErrorCounts() {
        let events = [event("other"), event("fault", detail: "IOAccel completed", severity: .fault),
                      event("isight-non-stall", detail: "Display iSight unrelated error")]
        let groups = SleepWakeReport.groupErrors(events)
        #expect(groups.count == 1)
        #expect(groups[0].category == .other && groups[0].count == 2)
    }

    @Test func explicitHCIContentAtInfoLevelRemainsVisibleWithoutChangingRawErrorCount() {
        let focus = focused(sequence())
        #expect(focus.errorGroups.isEmpty)
        #expect(focus.bluetoothSummary.hciFailureCount == 1)
        #expect(focus.bluetoothSummary.title.contains("controller-ready"))
        #expect(focus.bluetoothSummary.detail.contains("does not prove"))
        #expect(focus.bluetoothSummary.sequence.map(\.id) == ["hci", "exit", "start", "ready"])
    }

    @Test func completeWindowNoFurtherSignatureStatementIsTimeBounded() {
        let summary = focused(sequence()).bluetoothSummary
        #expect(summary.subsequentFailureCount == 0)
        #expect(summary.detail.contains("No further HCI failure signature"))
        #expect(summary.detail.contains(LogTimestamp.display(wake.addingTimeInterval(120), fractionalSeconds: true)))
        #expect(summary.detail.contains("queried logs"))
    }

    @Test func partialUnavailableOrOmittedEvidenceCannotClaimNoRecurrence() {
        for focus in [focused(sequence(), state: .partial), focused(sequence(), state: .unavailable), focused(sequence(), omitted: 1)] {
            let summary = focus.bluetoothSummary
            #expect(!summary.detail.contains("No further HCI"))
            #expect(summary.detail.contains("cannot establish no recurrence"))
        }
    }

    @Test func laterHCIFailurePreventsRecoveryNarrative() {
        let summary = focused(sequence() + [event("recurrence", offset: 12, bluetooth: .hciFailure)]).bluetoothSummary
        #expect(summary.hciFailureCount == 2)
        #expect(summary.subsequentFailureCount == 1)
        #expect(summary.title.contains("also recorded at or after"))
        #expect(!summary.detail.contains("No further HCI"))
    }

    @Test func failureAtDaemonStartTimestampCannotSupportNoRecurrenceClaim() {
        let summary = focused(sequence() + [event("ambiguous-order", offset: 5, bluetooth: .hciFailure)]).bluetoothSummary
        #expect(summary.subsequentFailureCount == 1)
        #expect(!summary.detail.contains("No further HCI"))
        #expect(summary.detail.contains("equal timestamps do not establish order"))
    }

    @Test func startWithoutExitDoesNotProveRestartAndStartWithoutReadyDoesNotProveRecovery() {
        let noExit = focused(sequence().filter { $0.bluetoothEvent != .daemonExit }).bluetoothSummary
        #expect(noExit.title.contains("exit was not captured"))
        let noReady = focused(sequence().filter { $0.bluetoothEvent != .controllerReady }).bluetoothSummary
        #expect(noReady.title.contains("controller recovery unverified"))
    }

    @Test func outOfWindowFailureCannotBecomePartOfFocusedStory() {
        let focus = focused([event("outside", offset: 130, bluetooth: .hciFailure)])
        #expect(focus.bluetoothSummary.hciFailureCount == 0)
        #expect(focus.bluetoothSummary.detail.contains("does not establish"))
    }

    @Test func queryUsesExplicitUTCOffsetAndStrictShortBounds() throws {
        let start = try #require(LogTimestamp.parse("2026-10-17 21:40:18 +0900"))
        let end = start.addingTimeInterval(420)
        let args = try #require(DiagnosticCommand.wakeIncidentArguments(since: start, until: end))
        #expect(args.contains("2026-10-17 12:40:18+0000"))
        #expect(args.contains("2026-10-17 12:47:18+0000"))
        #expect(args.contains("--start") && args.contains("--end") && !args.contains("--last"))
        #expect(DiagnosticCommand.wakeIncidentArguments(since: end, until: start) == nil)
        #expect(DiagnosticCommand.wakeIncidentArguments(since: start, until: start) == nil)
        #expect(DiagnosticCommand.wakeIncidentArguments(since: start, until: end.addingTimeInterval(1)) == nil)
        #expect(DiagnosticCommand.wakeIncidentArguments(since: Date(timeIntervalSince1970: .nan), until: end) == nil)
        #expect(DiagnosticCommand.wakeIncidentArguments(since: start, until: Date(timeIntervalSince1970: .infinity)) == nil)
        let evidence = CommandOutput(command: .wakeIncidentLog, windowStart: start, windowEnd: end).evidence
        #expect(evidence.source.contains("12:40:18+0000"))
    }

    @Test func unboundedFocusedCommandCannotLaunch() async {
        #expect(await CommandRunner().run(.wakeIncidentLog).termination == .launchFailed)
        #expect(await CommandRunner().runWakeIncidentLog(since: wake, until: wake.addingTimeInterval(421)).termination == .launchFailed)
        #expect(await CommandRunner().run(.wakeBluetoothLog).termination == .launchFailed)
        #expect(await CommandRunner().runWakeBluetoothLog(since: wake, until: wake.addingTimeInterval(421)).termination == .launchFailed)
        #expect(DiagnosticCommand.wakeBluetoothArguments(since: wake, until: wake.addingTimeInterval(420))?.last == DiagnosticCommand.bluetoothFailurePredicate)
        #expect(DiagnosticCommand.focusedPredicate != DiagnosticCommand.bluetoothFailurePredicate)
    }

    @Test func focusedDataAndCategoriesRoundTripAndLegacyEventsStillDecode() throws {
        let focus = focused(sequence())
        let report = SleepWakeReport(windowStart: focus.start, windowEnd: focus.end, events: focus.events,
            sources: [focus.coverage], focusedWake: focus)
        let data = try JSONEncoder().encode(report)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["errorGroups"] != nil)
        #expect((json["focusedWake"] as? [String: Any])?["bluetoothSummary"] != nil)
        let decoded = try JSONDecoder().decode(SleepWakeReport.self, from: data)
        #expect(decoded.focusedWake?.bluetoothSummary.hciFailureCount == 1)
        var legacy = json
        legacy.removeValue(forKey: "focusedWake")
        var events = try #require(legacy["events"] as? [[String: Any]])
        for i in events.indices { events[i].removeValue(forKey: "bluetoothEvent") }
        legacy["events"] = events
        let old = try JSONDecoder().decode(SleepWakeReport.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.focusedWake == nil && old.events.allSatisfy { $0.bluetoothEvent == nil })
    }

    @Test func textReportExplainsCategoriesBeforeAggregateAndFocusedOverlap() {
        let focus = focused(sequence() + [event("permission", detail: "not entitled to set wake reason")])
        let report = SleepWakeReport(windowStart: focus.start, windowEnd: focus.end, events: focus.events, sources: [focus.coverage], focusedWake: focus)
        let text = ReportGenerator.sleepWakeReport(report)
        #expect(text.range(of: "Wake-reason permission errors:")!.lowerBound < text.range(of: "Total Error-level records:")!.lowerBound)
        #expect(text.contains("do not add them to history totals"))
        #expect(text.contains("[Latest wake — focused evidence]"))
    }
}
