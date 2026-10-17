import Foundation

public enum SleepWakeErrorCategory: String, Codable, CaseIterable, Sendable {
    case bluetoothHCI = "Bluetooth HCI failures"
    case transitionFailure = "Sleep/wake failure signatures"
    case isightTransfer = "iSight transfer stalls"
    case usbExclusiveAccess = "USB exclusive-access conflicts"
    case wakePermission = "Wake-reason permission errors"
    case graphics = "Other graphics-related errors"
    case bluetoothOther = "Other Bluetooth errors"
    case other = "Other related errors"

    public var interpretation: String {
        switch self {
        case .bluetoothHCI: return "Explicit HCI failure records. Review controller and daemon lifecycle evidence; this does not establish a display-fault cause."
        case .transitionFailure: return "Explicit transition-failure signatures. Their cause and current impact remain unconfirmed."
        case .isightTransfer: return "The display camera reported a stalled USB transfer. This is not a GPU-failure count."
        case .usbExclusiveAccess: return "An application could not obtain exclusive USB access while another client held it. This does not by itself establish a hardware fault."
        case .wakePermission: return "A wake-reason API call was denied. This is not proof that resume failed."
        case .graphics: return "Graphics-related Error-level records; timing and an explicit symptom match still need review."
        case .bluetoothOther: return "Other Bluetooth Error-level records, kept separate from explicit HCI failure signatures."
        case .other: return "Other Error-level records, including diagnostic queries. They may lack a nearby sleep/wake anchor."
        }
    }
}

public struct SleepWakeErrorGroup: Identifiable, Codable, Equatable, Sendable {
    public var id: String { category.rawValue }
    public let category: SleepWakeErrorCategory
    public let count: Int
    public let latestAt: Date
    public var title: String { category.rawValue }
    public var interpretation: String { category.interpretation }
}

public extension SleepWakeEvent {
    /// Mutually exclusive classification of retained Error-level records; never an incident counter.
    var errorCategory: SleepWakeErrorCategory? {
        guard severity == .error else { return nil }
        let text = (title + " " + detail).lowercased()
        if bluetoothEvent == .hciFailure { return .bluetoothHCI }
        if kind == .failure { return .transitionFailure }
        if text.contains("not entitled to set wake reason") || title == "Wake-reason API permission error" { return .wakePermission }
        let exclusive = text.contains("exclusive access") || text.contains("exclusively opened") || text.contains("exclusively open")
        if exclusive, text.contains("usb") || text.contains("opengated") { return .usbExclusiveAccess }
        if text.contains("isight"), text.contains("stall") || text.contains("0xe0005000") { return .isightTransfer }
        if bluetoothEvent != nil || text.contains("bluetooth") { return .bluetoothOther }
        if title.lowercased().contains("graphics") { return .graphics }
        return .other
    }
}

public extension SleepWakeReport {
    var errorGroups: [SleepWakeErrorGroup] { Self.groupErrors(events) }

    static func groupErrors(_ events: [SleepWakeEvent]) -> [SleepWakeErrorGroup] {
        SleepWakeErrorCategory.allCases.compactMap { category in
            let matches = events.filter { $0.errorCategory == category }
            guard let latest = matches.map(\.timestamp).max() else { return nil }
            return SleepWakeErrorGroup(category: category, count: matches.count, latestAt: latest)
        }
    }
}

public struct BluetoothRecoverySummary: Codable, Sendable {
    public let title: String
    public let detail: String
    public let hciFailureCount: Int
    public let subsequentFailureCount: Int?
    public let firstHCIFailureAt: Date?
    public let lastHCIFailureAt: Date?
    public let recurrenceStart: Date?
    public let recurrenceEnd: Date?
    /// Includes compact timestamps whose millisecond precision overlaps the selected start.
    public let sameTimestampFailureCount: Int?
    public let countsAreFromFullScan: Bool
    public let hasCompleteCoverage: Bool
    /// A bounded chronological sample; counts above are calculated before this sample is made.
    public let sequence: [SleepWakeEvent]
    public let sequenceOmittedEventCount: Int

    fileprivate func restrictingCoverage() -> BluetoothRecoverySummary {
        guard hasCompleteCoverage else { return self }
        return BluetoothRecoverySummary(title: title,
            detail: FocusedWakeAnalysis.detail(failureCount: hciFailureCount, firstFailure: firstHCIFailureAt,
                recurrenceStart: recurrenceStart, recurrenceEnd: recurrenceEnd, subsequent: subsequentFailureCount,
                complete: false, fullScan: countsAreFromFullScan, sequenceOmitted: sequenceOmittedEventCount,
                instanceChangeAt: recurrenceStart == nil ? sequence.last { $0.bluetoothEvent == .daemonInstanceChange }?.timestamp : nil),
            hciFailureCount: hciFailureCount, subsequentFailureCount: subsequentFailureCount,
            firstHCIFailureAt: firstHCIFailureAt, lastHCIFailureAt: lastHCIFailureAt,
            recurrenceStart: recurrenceStart, recurrenceEnd: recurrenceEnd,
            sameTimestampFailureCount: sameTimestampFailureCount,
            countsAreFromFullScan: countsAreFromFullScan, hasCompleteCoverage: false,
            sequence: sequence, sequenceOmittedEventCount: sequenceOmittedEventCount)
    }
}

/// One recognized HCI row. Equal timestamps and severities do not identify duplicate rows.
public struct BluetoothFailureObservation: Sendable {
    public let timestamp: Date
    public let severity: LogSeverity

    public init(timestamp: Date, severity: LogSeverity) {
        self.timestamp = timestamp; self.severity = severity
    }
}

/// Counts every returned, recognized match before a display sample is selected.
/// Complete query coverage still does not imply that macOS retained every real-world event.
public struct FocusedWakeScanSummary: Codable, Sendable {
    public let start: Date
    public let end: Date
    public let coverage: LogSourceCoverage
    public let matchedEventCount: Int
    public let errorCount: Int
    public let faultCount: Int
    public let warningCount: Int
    public let errorGroups: [SleepWakeErrorGroup]
    public let bluetoothSummary: BluetoothRecoverySummary

    public init(events: [SleepWakeEvent], start: Date, end: Date, coverage: LogSourceCoverage,
                hciObservations: [BluetoothFailureObservation]? = nil) {
        self.start = start; self.end = end
        let validWindow = FocusedWakeAnalysis.validWindow(start: start, end: end)
        self.coverage = validWindow ? coverage : LogSourceCoverage(id: coverage.id, name: coverage.name,
            state: .unavailable, detail: "The requested focused interval is invalid.", evidence: coverage.evidence)
        let unique = FocusedWakeAnalysis.uniqueEvents(events, start: start, end: end)
        let observations = hciObservations.map { values in
            validWindow ? values.filter { $0.timestamp >= start && $0.timestamp <= end } : []
        }
        // Instance-change annotations describe existing source rows; they are not additional
        // collected records and must not inflate matching or source-severity counts.
        let sourceEvents = unique.filter { $0.bluetoothEvent != .daemonInstanceChange }
        let countedEvents = observations == nil ? sourceEvents : sourceEvents.filter { $0.bluetoothEvent != .hciFailure }
        matchedEventCount = countedEvents.count + (observations?.count ?? 0)
        errorCount = countedEvents.filter { $0.severity == .error }.count + (observations?.filter { $0.severity == .error }.count ?? 0)
        faultCount = countedEvents.filter { $0.severity == .fault }.count + (observations?.filter { $0.severity == .fault }.count ?? 0)
        warningCount = countedEvents.filter { $0.severity == .warning }.count + (observations?.filter { $0.severity == .warning }.count ?? 0)
        var groups = SleepWakeReport.groupErrors(countedEvents)
        if let observations {
            let errors = observations.filter { $0.severity == .error }
            if let latest = errors.map(\.timestamp).max() {
                groups.insert(SleepWakeErrorGroup(category: .bluetoothHCI, count: errors.count, latestAt: latest), at: 0)
            }
        }
        errorGroups = groups
        bluetoothSummary = FocusedWakeAnalysis.bluetooth(unique, end: end,
            complete: validWindow && coverage.state == .available, fullScan: true, observations: observations)
    }
}

public struct FocusedLogSegment: Identifiable, Codable, Sendable {
    public let id: String
    /// A fixed collector label, never a raw log message or process path.
    public let kind: String
    public let start: Date
    public let end: Date
    public let coverage: LogSourceCoverage

    public init(id: String, kind: String, start: Date, end: Date, coverage: LogSourceCoverage) {
        self.id = id; self.kind = kind; self.start = start; self.end = end; self.coverage = coverage
    }
}

public struct FocusedWakeEvidence: Codable, Sendable {
    public let wakeAt: Date
    public let start: Date
    public let end: Date
    /// Display samples, which may omit records already included in scanSummary counts.
    public let events: [SleepWakeEvent]
    public let coverage: LogSourceCoverage
    public let omittedEventCount: Int
    public let scanSummary: FocusedWakeScanSummary?
    public let segments: [FocusedLogSegment]?

    public init(wakeAt: Date, start: Date, end: Date, events: [SleepWakeEvent],
                coverage: LogSourceCoverage, omittedEventCount: Int = 0,
                scanSummary: FocusedWakeScanSummary? = nil, segments: [FocusedLogSegment]? = nil) {
        self.wakeAt = wakeAt; self.start = start; self.end = end; self.events = events
        self.coverage = coverage; self.scanSummary = scanSummary; self.segments = segments
        if let scanSummary, scanSummary.start == start, scanSummary.end == end {
            self.omittedEventCount = max(0, scanSummary.matchedEventCount
                - FocusedWakeAnalysis.uniqueEvents(events, start: start, end: end)
                    .filter { $0.bluetoothEvent != .daemonInstanceChange }.count)
        } else {
            self.omittedEventCount = max(0, omittedEventCount)
        }
    }

    public var displayedEventCount: Int { FocusedWakeAnalysis.uniqueEvents(events, start: start, end: end).count }
    public var derivedEventCount: Int {
        FocusedWakeAnalysis.uniqueEvents(events, start: start, end: end)
            .filter { $0.bluetoothEvent == .daemonInstanceChange }.count
    }
    public var sourceSampleEventCount: Int { displayedEventCount - derivedEventCount }
    public var matchedEventCount: Int { matchingSummary?.matchedEventCount ?? sourceSampleEventCount }
    private var matchingSummary: FocusedWakeScanSummary? {
        guard let scanSummary, scanSummary.start == start, scanSummary.end == end,
              scanSummary.matchedEventCount >= sourceSampleEventCount else { return nil }
        return scanSummary
    }
    public var errorGroups: [SleepWakeErrorGroup] {
        matchingSummary?.errorGroups
            ?? SleepWakeReport.groupErrors(FocusedWakeAnalysis.uniqueEvents(events, start: start, end: end)
                .filter { $0.bluetoothEvent != .daemonInstanceChange })
    }
    public var hasIncompleteCoverage: Bool {
        guard FocusedWakeAnalysis.validWindow(start: start, end: end), coverage.state == .available,
              !(segments?.contains { $0.coverage.state != .available } ?? false) else { return true }
        if let summary = matchingSummary { return summary.coverage.state != .available }
        // Old snapshots only counted retained samples. Their omitted records remain an evidence gap.
        return scanSummary != nil || omittedEventCount > 0
    }

    public var bluetoothSummary: BluetoothRecoverySummary {
        if let summary = matchingSummary {
            return hasIncompleteCoverage ? summary.bluetoothSummary.restrictingCoverage() : summary.bluetoothSummary
        }
        return FocusedWakeAnalysis.bluetooth(FocusedWakeAnalysis.uniqueEvents(events, start: start, end: end),
            end: end, complete: !hasIncompleteCoverage, fullScan: false)
    }

    private enum CodingKeys: String, CodingKey { case wakeAt, start, end, events, coverage, omittedEventCount, scanSummary, segments }
    private enum DerivedKeys: String, CodingKey {
        case errorGroups, bluetoothSummary, matchedEventCount, displayedEventCount, derivedEventCount, sourceSampleEventCount
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(wakeAt: try c.decode(Date.self, forKey: .wakeAt), start: try c.decode(Date.self, forKey: .start),
            end: try c.decode(Date.self, forKey: .end), events: try c.decode([SleepWakeEvent].self, forKey: .events),
            coverage: try c.decode(LogSourceCoverage.self, forKey: .coverage),
            omittedEventCount: try c.decodeIfPresent(Int.self, forKey: .omittedEventCount) ?? 0,
            scanSummary: try c.decodeIfPresent(FocusedWakeScanSummary.self, forKey: .scanSummary),
            segments: try c.decodeIfPresent([FocusedLogSegment].self, forKey: .segments))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(wakeAt, forKey: .wakeAt); try c.encode(start, forKey: .start); try c.encode(end, forKey: .end)
        try c.encode(events, forKey: .events); try c.encode(coverage, forKey: .coverage)
        try c.encode(omittedEventCount, forKey: .omittedEventCount)
        try c.encodeIfPresent(scanSummary, forKey: .scanSummary); try c.encodeIfPresent(segments, forKey: .segments)
        var derived = encoder.container(keyedBy: DerivedKeys.self)
        try derived.encode(errorGroups, forKey: .errorGroups)
        try derived.encode(bluetoothSummary, forKey: .bluetoothSummary)
        try derived.encode(matchedEventCount, forKey: .matchedEventCount)
        try derived.encode(displayedEventCount, forKey: .displayedEventCount)
        try derived.encode(derivedEventCount, forKey: .derivedEventCount)
        try derived.encode(sourceSampleEventCount, forKey: .sourceSampleEventCount)
    }
}

private enum FocusedWakeAnalysis {
    static func validWindow(start: Date, end: Date) -> Bool {
        start.timeIntervalSince1970.isFinite && end.timeIntervalSince1970.isFinite && start < end
    }

    static func chronological(_ lhs: SleepWakeEvent, _ rhs: SleepWakeEvent) -> Bool {
        lhs.timestamp == rhs.timestamp ? lhs.id < rhs.id : lhs.timestamp < rhs.timestamp
    }

    static func uniqueEvents(_ events: [SleepWakeEvent], start: Date, end: Date) -> [SleepWakeEvent] {
        guard validWindow(start: start, end: end) else { return [] }
        var seen = Set<String>()
        return events.filter { $0.timestamp >= start && $0.timestamp <= end }
            .sorted(by: chronological).filter { seen.insert($0.id).inserted }
    }

    static func bluetooth(_ events: [SleepWakeEvent], end: Date, complete: Bool, fullScan: Bool,
                          observations: [BluetoothFailureObservation]? = nil) -> BluetoothRecoverySummary {
        let all = events.filter { $0.bluetoothEvent != nil }
        // Compact HCI rows are authoritative when supplied. Equal millisecond timestamps
        // can describe thousands of distinct rows and must never be deduplicated here.
        let failures = observations ?? all.filter { $0.bluetoothEvent == .hciFailure }
            .map { BluetoothFailureObservation(timestamp: $0.timestamp, severity: $0.severity) }
        let firstFailure = failures.min { $0.timestamp < $1.timestamp }
        let lastFailure = failures.max { $0.timestamp < $1.timestamp }
        let coarse = observations != nil
        let starts = all.filter { event in
            guard event.bluetoothEvent == .daemonStart, let firstFailure else { return false }
            return coarse ? event.timestamp >= firstFailure.timestamp.addingTimeInterval(0.001)
                : event.timestamp > firstFailure.timestamp
        }
        let exits = all.filter { $0.bluetoothEvent == .daemonExit && $0.timestamp >= (firstFailure?.timestamp ?? end) }
        // Prefer the latest explicitly ordered exit -> start pair. Simultaneous records
        // cannot establish this order, regardless of their display-ID tie breaker.
        let restarts: [(exit: SleepWakeEvent, start: SleepWakeEvent)] = starts.compactMap { started in
            guard !exits.contains(where: { $0.timestamp == started.timestamp }),
                  let exited = exits.last(where: { $0.timestamp < started.timestamp }) else { return nil }
            return (exited, started)
        }
        let selectedRestart = restarts.last
        let started = selectedRestart?.start ?? starts.last
        let exited = selectedRestart?.exit
        let nextExit = started.flatMap { started in exits.first { $0.timestamp > started.timestamp } }
        let recurrenceEnd = started.map { _ in min(end, nextExit?.timestamp ?? end) }
        let ready = all.first { event in
            event.bluetoothEvent == .controllerReady
                && event.timestamp > (started?.timestamp ?? firstFailure?.timestamp ?? end)
                && event.timestamp <= (recurrenceEnd ?? end)
                && (nextExit.map { event.timestamp < $0.timestamp } ?? true)
        }
        let subsequent = started.map { started in
            failures.filter {
                ($0.timestamp >= started.timestamp || (coarse && started.timestamp.timeIntervalSince($0.timestamp) < 0.001))
                    && $0.timestamp <= (recurrenceEnd ?? end)
            }.count
        }
        let simultaneous = started.map { started in
            failures.filter {
                $0.timestamp == started.timestamp || (coarse && $0.timestamp < started.timestamp
                    && started.timestamp.timeIntervalSince($0.timestamp) < 0.001)
            }.count
        }
        let instanceChange = all.last { $0.bluetoothEvent == .daemonInstanceChange }

        let title: String
        if started == nil, let instanceChange {
            title = failures.contains { $0.timestamp >= instanceChange.timestamp }
                ? "Later HCI failure came from a different Bluetooth daemon process"
                : "Different Bluetooth daemon processes were observed"
        } else if firstFailure == nil {
            title = complete ? "No HCI failure signature in the \(fullScan ? "scanned" : "retained") focused evidence"
                : "No HCI failure signature in the available focused evidence; coverage is incomplete"
        } else if let subsequent, subsequent > 0 {
            title = "HCI failures were also recorded at or after the daemon start"
        } else if started != nil && exited != nil {
            title = ready == nil ? "Daemon exit and start recorded; controller recovery unverified" : "A controller-ready record followed the daemon restart"
        } else if let started {
            title = exits.contains(where: { $0.timestamp == started.timestamp })
                ? "A daemon start followed HCI failure; exit/start ordering is unverified"
                : "A daemon start followed HCI failure; an exit was not captured"
        } else if ready != nil {
            title = "A controller-ready record followed HCI failure; restart unverified"
        } else {
            title = "HCI failure recorded; subsequent recovery is unverified"
        }
        // Sample representatives do not supply the counts. If a compact observation lacks
        // a corresponding retained row, create only a privacy-safe endpoint representative.
        let hciSamples = all.filter { $0.bluetoothEvent == .hciFailure }
        let firstSample = firstFailure.map { observation in
            hciSamples.first { $0.timestamp == observation.timestamp && $0.severity == observation.severity }
                ?? representative(observation, endpoint: "first")
        }
        let lastSample: SleepWakeEvent?
        if failures.count > 1, let lastFailure {
            lastSample = hciSamples.last { $0.timestamp == lastFailure.timestamp && $0.severity == lastFailure.severity && $0.id != firstSample?.id }
                ?? representative(lastFailure, endpoint: "last")
        } else { lastSample = nil }
        let essential = [firstSample, lastSample, exited, started, ready, instanceChange].compactMap { $0 }
        let lifecycle = all.filter { $0.bluetoothEvent != .hciFailure }
        var sampleIDs = Set<String>()
        let sequence = Array((essential + Array(lifecycle.reversed())).filter { sampleIDs.insert($0.id).inserted }.prefix(100))
            .sorted(by: chronological)
        let omitted = max(0, failures.count + lifecycle.count - sequence.count)
        return BluetoothRecoverySummary(title: title,
            detail: detail(failureCount: failures.count, firstFailure: firstFailure?.timestamp,
                recurrenceStart: started?.timestamp, recurrenceEnd: recurrenceEnd, subsequent: subsequent,
                complete: complete, fullScan: fullScan, sequenceOmitted: omitted,
                instanceChangeAt: started == nil ? instanceChange?.timestamp : nil),
            hciFailureCount: failures.count, subsequentFailureCount: subsequent,
            firstHCIFailureAt: firstFailure?.timestamp, lastHCIFailureAt: lastFailure?.timestamp,
            recurrenceStart: started?.timestamp, recurrenceEnd: recurrenceEnd, sameTimestampFailureCount: simultaneous,
            countsAreFromFullScan: fullScan, hasCompleteCoverage: complete,
            sequence: sequence, sequenceOmittedEventCount: omitted)
    }

    private static func representative(_ observation: BluetoothFailureObservation, endpoint: String) -> SleepWakeEvent {
        SleepWakeEvent(id: "focused-hci-\(endpoint)-\(observation.timestamp.timeIntervalSince1970)-\(observation.severity.rawValue)",
            timestamp: observation.timestamp, kind: observation.severity == .error ? .relatedError : .relatedRecord,
            severity: observation.severity, title: "Bluetooth HCI failure signature",
            detail: "Representative of a parsed HCI failure record. The original message is not retained; source severity is preserved.",
            source: "Unified Sleep/Wake Log", evidence: [], bluetoothEvent: .hciFailure)
    }

    static func detail(failureCount: Int, firstFailure: Date?, recurrenceStart: Date?, recurrenceEnd: Date?,
                       subsequent: Int?, complete: Bool, fullScan: Bool, sequenceOmitted: Int,
                       instanceChangeAt: Date? = nil) -> String {
        let basis = fullScan ? "observed before display sampling" : "retained"
        var detail = "\(failureCount) \(basis) HCI failure signature(s)"
        detail += firstFailure.map { ", beginning \(LogTimestamp.display($0, fractionalSeconds: true)). " } ?? ". "
        if let instanceChangeAt {
            detail += "A different Bluetooth daemon process was observed at \(LogTimestamp.display(instanceChangeAt, fractionalSeconds: true)). A process change is consistent with a restart, but the exact start, exit and cause are unverified. This is not an explicit daemon-start record and does not establish a recurrence-free interval. "
        }
        if let recurrenceStart, let recurrenceEnd, let subsequent {
            detail += "The recurrence interval uses the selected daemon start and ends at the next recorded exit or the requested window end. "
            if subsequent == 0 && complete && recurrenceStart < recurrenceEnd {
                detail += "No further HCI failure signature was found in the queried logs from \(LogTimestamp.display(recurrenceStart, fractionalSeconds: true)) to \(LogTimestamp.display(recurrenceEnd, fractionalSeconds: true)). "
            } else {
                detail += "\(subsequent) \(basis) HCI failure signature(s) at or after the daemon start, from \(LogTimestamp.display(recurrenceStart, fractionalSeconds: true)) through \(LogTimestamp.display(recurrenceEnd, fractionalSeconds: true)); equal timestamps do not establish order. "
            }
            if recurrenceStart >= recurrenceEnd { detail += "There is no positive observation interval after this start; recurrence remains unverified. " }
        }
        if !complete { detail += "Coverage is incomplete, so absence of another record cannot establish no recurrence. " }
        if sequenceOmitted > 0 { detail += "The chronological sequence is a sample; \(sequenceOmitted) Bluetooth record(s) are omitted from that display, but included in the counts above. " }
        detail += "Compact HCI timestamps have millisecond precision; a timestamp bucket overlapping the daemon start cannot establish event order. This applies only to the collected window and does not establish that no failure occurred outside available logs. Event order is temporal evidence, not causation. A started daemon or ready controller does not prove that Bluetooth devices or the display recovered."
        return detail
    }
}
