import Foundation

public enum SleepWakeKind: String, Codable, CaseIterable, Sendable {
    case sleep = "Sleep"
    case wake = "Wake"
    case darkWake = "Dark Wake"
    case failure = "Failure"
    case relatedError = "Related Error"
    case relatedRecord = "Related Record"
}

public enum LogSeverity: String, Codable, CaseIterable, Sendable {
    case information = "Info"
    case warning = "Warning"
    case error = "Error"
    case fault = "Fault"
}

public enum LogCoverageState: String, Codable, Sendable {
    case available = "Available"
    case partial = "Partial"
    case unavailable = "Unavailable"
}

public enum BluetoothEventKind: String, Codable, Sendable {
    case hciFailure = "HCI failure"
    case daemonExit = "Daemon exit"
    case daemonStart = "Daemon start"
    case daemonInstanceChange = "Different daemon process observed"
    case controllerReady = "Controller ready"
}

public struct LogSourceCoverage: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let state: LogCoverageState
    public let detail: String
    public let evidence: [Evidence]
    public init(id: String, name: String, state: LogCoverageState, detail: String, evidence: [Evidence]) {
        self.id = id; self.name = name; self.state = state; self.detail = detail; self.evidence = evidence
    }
}

public struct SleepWakeEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let timestamp: Date
    public let kind: SleepWakeKind
    public let severity: LogSeverity
    public let title: String
    public let detail: String
    public let source: String
    public let evidence: [Evidence]
    /// Temporal proximity only. Never a claim of causation or a completed wake.
    public let correlation: String?
    public let bluetoothEvent: BluetoothEventKind?

    public init(id: String, timestamp: Date, kind: SleepWakeKind, severity: LogSeverity,
                title: String, detail: String, source: String, evidence: [Evidence], correlation: String? = nil,
                bluetoothEvent: BluetoothEventKind? = nil) {
        self.id = id; self.timestamp = timestamp; self.kind = kind; self.severity = severity
        self.title = title; self.detail = detail; self.source = source
        self.evidence = evidence; self.correlation = correlation
        self.bluetoothEvent = bluetoothEvent
    }
}

public struct SleepWakeReport: Codable, Sendable {
    public let windowStart: Date
    public let windowEnd: Date
    public let events: [SleepWakeEvent]
    public let sources: [LogSourceCoverage]
    public let isDemo: Bool
    public let omittedEventCount: Int
    public let focusedWake: FocusedWakeEvidence?

    public init(windowStart: Date, windowEnd: Date, events: [SleepWakeEvent],
                sources: [LogSourceCoverage], isDemo: Bool = false, omittedEventCount: Int = 0,
                focusedWake: FocusedWakeEvidence? = nil) {
        self.windowStart = windowStart; self.windowEnd = windowEnd; self.events = events
        self.sources = sources; self.isDemo = isDemo; self.omittedEventCount = omittedEventCount
        self.focusedWake = focusedWake
    }
    public var errorCount: Int { events.filter { $0.severity == .error }.count }
    public var warningCount: Int { events.filter { $0.severity == .warning }.count }
    public var faultCount: Int { events.filter { $0.severity == .fault }.count }
    public var latestError: SleepWakeEvent? {
        events.filter { $0.severity == .error }.max { $0.timestamp < $1.timestamp }
    }
    public var hasIncompleteCoverage: Bool {
        sources.isEmpty || sources.contains { $0.state != .available } || omittedEventCount > 0
            || focusedWake?.hasIncompleteCoverage == true
    }
    private enum CodingKeys: String, CodingKey { case windowStart, windowEnd, events, sources, isDemo, omittedEventCount, focusedWake }
    private enum DerivedKeys: String, CodingKey { case errorGroups }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(windowStart, forKey: .windowStart); try c.encode(windowEnd, forKey: .windowEnd)
        try c.encode(events, forKey: .events); try c.encode(sources, forKey: .sources)
        try c.encode(isDemo, forKey: .isDemo); try c.encode(omittedEventCount, forKey: .omittedEventCount)
        try c.encodeIfPresent(focusedWake, forKey: .focusedWake)
        var derived = encoder.container(keyedBy: DerivedKeys.self)
        try derived.encode(errorGroups, forKey: .errorGroups)
    }
    public var section: DiagnosticSection {
        DiagnosticSection(id: "sleepWake", title: "Sleep & Wake", items: [
            DiagnosticItem(id: "sleepWakeErrors", label: "Sleep/wake-related error records", value: String(errorCount),
                status: errorCount > 0 ? .attention : .unknown,
                message: errorCount > 0 ? "Errors were recorded in the collected evidence. Their cause and current impact are unconfirmed." : "No matching errors were found in the collected evidence. This does not prove that sleep or resume succeeded.",
                evidence: sources.flatMap(\.evidence)),
            DiagnosticItem(id: "sleepWakeFaults", label: "Fault-level records", value: String(faultCount),
                status: .unknown,
                message: "A source log level is not a diagnosis. Graphics drivers can emit completion traces at Fault level; these are counted separately from error records.", evidence: sources.flatMap(\.evidence)),
            DiagnosticItem(id: "sleepWakeCoverage", label: "Log coverage", value: hasIncompleteCoverage ? "Incomplete" : "Requested sources read",
                status: hasIncompleteCoverage ? .unknown : .healthy,
                message: "Requested window: seven days. Retention, privacy redaction and collection limits can hide events. A wake entry is not proof of a usable desktop.", evidence: sources.flatMap(\.evidence))
        ])
    }
}
