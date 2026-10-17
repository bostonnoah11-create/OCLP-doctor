import Foundation

public enum DemoSleepWake {
    public static func report(now: Date = Date(), unavailable: Bool = false) -> SleepWakeReport {
        let source = LogSourceCoverage(id: "demo-logs", name: "Synthetic fixture",
            state: unavailable ? .unavailable : .available,
            detail: unavailable ? "Synthetic unavailable-source scenario. No real log files were read." : "Synthetic timeline for UI validation. These are not events from this Mac.",
            evidence: [Evidence(source: "Synthetic fixture", detail: "No system logs were read.")])
        let events = unavailable ? [] : [
            SleepWakeEvent(id: "demo-bluetooth-ready", timestamp: now.addingTimeInterval(-110), kind: .relatedRecord, severity: .information,
                title: "Bluetooth controller ready (demo)", detail: "Synthetic controller-ready record; device operation was not tested.",
                source: "Unified log (demo)", evidence: source.evidence, bluetoothEvent: .controllerReady),
            SleepWakeEvent(id: "demo-bluetooth-start", timestamp: now.addingTimeInterval(-112), kind: .relatedRecord, severity: .information,
                title: "Bluetooth daemon start (demo)", detail: "Synthetic launchd service-start record.",
                source: "Unified log (demo)", evidence: source.evidence, bluetoothEvent: .daemonStart),
            SleepWakeEvent(id: "demo-bluetooth-exit", timestamp: now.addingTimeInterval(-114), kind: .relatedRecord, severity: .information,
                title: "Bluetooth daemon exit (demo)", detail: "Synthetic launchd service-exit record.",
                source: "Unified log (demo)", evidence: source.evidence, bluetoothEvent: .daemonExit),
            SleepWakeEvent(id: "demo-bluetooth-failure", timestamp: now.addingTimeInterval(-117), kind: .relatedError, severity: .error,
                title: "Bluetooth HCI failure (demo)", detail: "Synthetic HCI command failure.",
                source: "Unified log (demo)", evidence: source.evidence, bluetoothEvent: .hciFailure),
            SleepWakeEvent(id: "demo-fault-trace", timestamp: now.addingTimeInterval(-116), kind: .relatedRecord, severity: .fault,
                title: "Fault-level graphics record (demo)", detail: "Synthetic example: IOAccelDisplayPipe::display_change_handler completed.",
                source: "Unified log (demo)", evidence: source.evidence,
                correlation: "Fault is the source log level. A completion trace does not prove a graphics failure."),
            SleepWakeEvent(id: "demo-wake-error", timestamp: now.addingTimeInterval(-117), kind: .failure, severity: .error,
                title: "Wake transition timeout (demo)", detail: "Synthetic example: Wake transition timed out after 180 seconds.",
                source: "Diagnostic report (demo)", evidence: source.evidence,
                correlation: "Recorded near the demo wake entry. Timing alone does not identify a cause."),
            SleepWakeEvent(id: "demo-wake", timestamp: now.addingTimeInterval(-120), kind: .wake, severity: .information,
                title: "Wake recorded (demo)", detail: "Synthetic example: Wake from Normal Sleep.", source: "Power history (demo)", evidence: source.evidence),
            SleepWakeEvent(id: "demo-dark-wake", timestamp: now.addingTimeInterval(-600), kind: .darkWake, severity: .information,
                title: "Background wake recorded (demo)", detail: "Synthetic example: DarkWake for maintenance. This is not classified as an error.", source: "Power history (demo)", evidence: source.evidence),
            SleepWakeEvent(id: "demo-sleep", timestamp: now.addingTimeInterval(-1800), kind: .sleep, severity: .information,
                title: "Sleep recorded (demo)", detail: "Synthetic example: Entering Sleep state due to Idle Sleep.", source: "Power history (demo)", evidence: source.evidence)
        ]
        let focused = unavailable ? nil : FocusedWakeEvidence(wakeAt: now.addingTimeInterval(-120),
            start: now.addingTimeInterval(-420), end: now,
            events: events.filter { $0.timestamp >= now.addingTimeInterval(-420) }, coverage: source)
        return SleepWakeReport(windowStart: now.addingTimeInterval(-7 * 86400), windowEnd: now,
                              events: events, sources: [source], isDemo: true, focusedWake: focused)
    }
}
