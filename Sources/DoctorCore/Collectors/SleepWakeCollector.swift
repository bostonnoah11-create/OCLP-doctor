import Foundation

/// Collects a bounded history of evidence. Event proximity never establishes causation.
public struct SleepWakeCollector: Sendable {
    private let runner: any CommandExecuting
    private let reportCollector: DiagnosticReportCollector
    private static let eventLimit = 500
    private static let powerSource = "Power Management History"
    private static let unifiedSource = "Unified Sleep/Wake Log"

    public init(runner: any CommandExecuting, reportCollector: DiagnosticReportCollector = DiagnosticReportCollector()) {
        self.runner = runner
        self.reportCollector = reportCollector
    }

    public func collect(now: Date = Date()) async -> SleepWakeReport {
        let since = now.addingTimeInterval(-7 * 24 * 60 * 60)
        // Find the latest full Wake before querying its narrow incident window. The broad
        // history may time out; it must not delay this higher-value query.
        let powerOutput = await runner.run(.powerHistory)
        let power = Self.parsePower(powerOutput, since: since, until: now)
        let anchors = power.events.filter { [.sleep, .wake, .darkWake].contains($0.kind) }.map(\.timestamp)
        let wakeAnchors = power.events.filter { $0.kind == .wake }.map(\.timestamp)
        var focused: FocusedWakeEvidence?
        var focusedEvents = [SleepWakeEvent]()
        var focusedHiddenMatchCount = 0
        if let wake = wakeAnchors.max() {
            let start = Date(timeIntervalSince1970: ceil(max(since, wake.addingTimeInterval(-300)).timeIntervalSince1970))
            let end = Date(timeIntervalSince1970: floor(min(now, wake.addingTimeInterval(120)).timeIntervalSince1970))
            async let incidentTask = runner.runWakeIncidentLog(since: start, until: end)
            async let lifecycleTask = runner.runWakeBluetoothLifecycleLog(since: start, until: end)
            async let bluetoothTask = collectBluetooth(since: start, until: end, wake: wake)
            let (incidentOutput, lifecycleOutput, bluetooth) = await (incidentTask, lifecycleTask, bluetoothTask)
            let incident = Self.parseUnified(incidentOutput, anchors: anchors, wakeAnchors: [wake], since: start, until: end)
            let lifecycle = Self.parseUnified(lifecycleOutput, anchors: anchors, wakeAnchors: [wake], since: start, until: end)
            let otherEvents = Self.deduplicated(incident.events + lifecycle.events)
            focusedEvents = Self.deduplicated(otherEvents + bluetooth.events)
            // HCI in legacy NDJSON fixtures is supported without double-counting identical
            // rows in the dedicated query. Production graphics/lifecycle predicates omit it.
            var observations = bluetooth.observations
            observations += otherEvents.filter { $0.bluetoothEvent == .hciFailure && !bluetooth.legacyIDs.contains($0.id) }
                .map { BluetoothFailureObservation(timestamp: $0.timestamp, severity: $0.severity) }
            let segments = [
                Self.segment(id: "wake-incident", kind: "Power and graphics", start: start, end: end, coverage: incident.coverage),
                Self.segment(id: "wake-lifecycle", kind: "Bluetooth lifecycle", start: start, end: end, coverage: lifecycle.coverage)
            ] + bluetooth.segments
            let queryCoverage = Self.focusedCoverage(segments: segments, start: start, end: end)
            let summary = FocusedWakeScanSummary(events: focusedEvents, start: start, end: end,
                coverage: queryCoverage, hciObservations: observations)
            let retained = Self.retainingContext(focusedEvents)
            focusedHiddenMatchCount = max(0, summary.matchedEventCount - focusedEvents.count)
            focused = FocusedWakeEvidence(wakeAt: wake, start: start, end: end,
                events: retained, coverage: queryCoverage, scanSummary: summary, segments: segments)
        }
        async let unifiedTask = runner.run(.sleepWakeLog)
        async let recentTask = runner.run(.sleepWakeRecentLog)
        async let reportsTask = reportCollector.collect(since: since, until: now)
        let (unifiedOutput, recentOutput, reports) = await (unifiedTask, recentTask, reportsTask)
        let unified = Self.parseUnified(unifiedOutput, anchors: anchors, wakeAnchors: wakeAnchors, since: since, until: now)
        let recent = Self.parseUnified(recentOutput, anchors: anchors, wakeAnchors: wakeAnchors, since: since, until: now)
        let unifiedCoverage = Self.combinedUnifiedCoverage(historical: unified.coverage, recent: recent.coverage)
        let unique = Self.deduplicated((power.events + focusedEvents + recent.events + unified.events + reports.events)
            .filter { $0.timestamp >= since && $0.timestamp <= now })
        let retained = Self.retainingContext(unique)
        return SleepWakeReport(windowStart: since, windowEnd: now, events: retained,
            sources: [power.coverage, unifiedCoverage, reports.coverage],
            omittedEventCount: unique.count - retained.count + focusedHiddenMatchCount, focusedWake: focused)
    }

    private struct BluetoothScanBatch: Sendable {
        var events = [SleepWakeEvent]()
        var observations = [BluetoothFailureObservation]()
        var legacyIDs = Set<String>()
        var segments = [FocusedLogSegment]()
        var processRanges = [String: BluetoothProcessRange]()
        var processRangeOverflow = false
    }

    private struct BluetoothProcessRange: Sendable {
        var first: Date
        var last: Date
    }

    private struct BluetoothCandidate {
        let timestamp: Date
        let severity: LogSeverity
        let id: String
    }

    private func collectBluetooth(since: Date, until: Date, wake: Date) async -> BluetoothScanBatch {
        // Read the quiet later interval first, then the pre-Wake interval, then the dense
        // initial burst. Each interval has independent completion and coverage evidence.
        let wakeBoundary = Date(timeIntervalSince1970: floor(wake.timeIntervalSince1970))
        let split = wakeBoundary.addingTimeInterval(10)
        let windows: [(String, String, Date, Date)] = [
            ("wake-hci-after", "Bluetooth HCI after initial Wake", max(since, split), until),
            ("wake-hci-before", "Bluetooth HCI before Wake", since, min(until, wakeBoundary)),
            ("wake-hci-initial", "Bluetooth HCI initial Wake", max(since, wakeBoundary), min(until, split))
        ]
        var result = BluetoothScanBatch()
        for (id, kind, start, end) in windows where end > start {
            let output = await runner.runWakeBluetoothLog(since: start, until: end)
            let scan = Self.parseBluetoothWindow(output, start: start, end: end,
                includeEnd: end == until, wake: wake, sliceID: id)
            result.events = Self.retainingContext(Self.deduplicated(result.events + scan.events))
            result.observations += scan.observations
            result.legacyIDs.formUnion(scan.legacyIDs)
            result.segments += scan.segments.map { Self.segment(id: id, kind: kind, start: start, end: end, coverage: $0.coverage) }
            result.processRangeOverflow = result.processRangeOverflow || scan.processRangeOverflow
            for (identity, range) in scan.processRanges {
                if let existing = result.processRanges[identity] {
                    result.processRanges[identity] = BluetoothProcessRange(first: min(existing.first, range.first), last: max(existing.last, range.last))
                } else if result.processRanges.count < 64 { result.processRanges[identity] = range }
                else { result.processRangeOverflow = true }
            }
        }
        let ranges = result.processRanges.values.sorted { $0.first < $1.first }
        var earlierRangeEnd: Date?
        for next in ranges {
            let previousEnd = earlierRangeEnd
            earlierRangeEnd = max(earlierRangeEnd ?? next.last, next.last)
            // Compare against every earlier range; an overlapping long-lived process
            // must not be hidden by a shorter intervening process range.
            guard let previousEnd, previousEnd < next.first else { continue }
            result.events.append(SleepWakeEvent(id: Self.stableID("bluetooth-instance-change|" + String(next.first.timeIntervalSince1970)),
                timestamp: next.first, kind: .relatedRecord, severity: .information,
                title: "Different Bluetooth daemon process observed",
                detail: "Later records came from a different bluetoothd process. Exact exit/start time and cause are not established.",
                source: Self.unifiedSource, evidence: [Evidence(source: Self.unifiedSource,
                    detail: "Non-overlapping groups of HCI records used different process identities. Raw process identifiers are omitted.")],
                correlation: "This is evidence of a process-instance change between observations, not an exact restart time or proof that Bluetooth devices recovered.",
                bluetoothEvent: .daemonInstanceChange))
        }
        if result.processRangeOverflow {
            result.segments = result.segments.map { item in
                let current = item.coverage
                return Self.segment(id: item.id, kind: item.kind, start: item.start, end: item.end,
                    coverage: LogSourceCoverage(id: current.id, name: current.name,
                        state: current.state == .available ? .partial : current.state,
                        detail: current.detail + " The bounded process-identity tracking limit was exceeded; process-change evidence may be incomplete.", evidence: current.evidence))
            }
        }
        result.events = Self.retainingContext(Self.deduplicated(result.events))
        return result
    }

    private static let compactRow = try! NSRegularExpression(
        pattern: #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})[ \t]+(Df|I|D|E|F)[ \t]+bluetoothd\[(\d{1,10}):[^\]]+\][ \t]*(.*)$"#)
    private static let hciName = try! NSRegularExpression(pattern: #"(?i)\bhci(?:controller|transport|command)?\b"#)
    private static let hciFailure = try! NSRegularExpression(pattern: #"(?i)\b(?:failed|failure|error|timeout|timed out|command disallowed)\b"#)

    private static func parseBluetoothWindow(_ output: CommandOutput, start: Date, end: Date,
                                            includeEnd: Bool, wake: Date, sliceID: String) -> BluetoothScanBatch {
        var result = BluetoothScanBatch()
        var scan = emptyScan(id: sliceID, name: "Bluetooth HCI")
        let commandEvidence = output.evidence
        let timestampParser = LogTimestampParser()
        var secondText = "", secondDate: Date?
        var previousTime = "", previousDate: Date?
        var first: BluetoothCandidate?
        var tail = [BluetoothCandidate]()
        var tailIndex = 0
        var ordinal = 0
        let compactIDPrefix = stableID(sliceID + "|" + String(start.timeIntervalSince1970) + "|" + String(end.timeIntervalSince1970))
        output.stdout.enumerateLines { rawLine, _ in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return }
            if line.hasPrefix("Timestamp") { scan.skipped += 1; return }
            ordinal += 1
            let timestamp: Date
            let severity: LogSeverity
            let message: String
            let id: String
            let processIdentity: String?
            if line.hasPrefix("{") {
                // NDJSON remains supported for saved fixtures and older command providers.
                guard let data = line.data(using: .utf8),
                      let dictionary = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    scan.malformed += 1; return
                }
                if Set(dictionary.keys) == Set(["count", "finished"]),
                   let count = dictionary["count"] as? Int, count >= 0, dictionary["finished"] as? Bool == true {
                    scan.skipped += 1; return
                }
                guard let rawTime = dictionary["timestamp"] as? String,
                      let date = timestampParser.parse(rawTime),
                      let text = dictionary["eventMessage"] as? String else { scan.malformed += 1; return }
                let process = (dictionary["processImagePath"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
                guard process == "bluetoothd" else { scan.skipped += 1; return }
                let type = (dictionary["messageType"] as? String)?.lowercased() ?? ""
                timestamp = date; message = text; severity = sourceSeverity(type)
                id = stableID([rawTime, process, text, type].joined(separator: "\u{1f}"))
                processIdentity = (dictionary["processID"] as? Int).flatMap { $0 >= 0 ? String($0) : nil }
            } else {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard let match = compactRow.firstMatch(in: line, range: range),
                      let timeRange = Range(match.range(at: 1), in: line),
                      let typeRange = Range(match.range(at: 2), in: line),
                      let pidRange = Range(match.range(at: 3), in: line),
                      let textRange = Range(match.range(at: 4), in: line) else { scan.malformed += 1; return }
                let rawTime = String(line[timeRange])
                if rawTime == previousTime, let date = previousDate {
                    timestamp = date
                } else {
                    let second = String(rawTime.prefix(19))
                    if second != secondText {
                        secondText = second
                        // compact uses the fixed command's explicit UTC display timezone.
                        secondDate = timestampParser.parse(second + " +0000")
                    }
                    guard let base = secondDate, let milliseconds = Int(rawTime.suffix(3)) else {
                        scan.malformed += 1; return
                    }
                    timestamp = base.addingTimeInterval(Double(milliseconds) / 1_000)
                    previousTime = rawTime; previousDate = timestamp
                }
                switch line[typeRange] {
                case "E": severity = .error
                case "F": severity = .fault
                default: severity = .information
                }
                message = String(line[textRange])
                processIdentity = String(line[pidRange])
                // Compact loses sub-millisecond precision. Identical adjacent rows remain
                // distinct observations, rather than being silently collapsed by timestamp.
                id = compactIDPrefix + "-row-" + String(ordinal)
            }
            scan.parsed += 1
            guard timestamp >= start, timestamp < end || (includeEnd && timestamp <= end) else {
                scan.outsideWindow += 1; return
            }
            let value = strippedBenignText(message)
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            guard hciName.firstMatch(in: value, range: range) != nil,
                  hciFailure.firstMatch(in: value, range: range) != nil else { scan.skipped += 1; return }
            if line.hasPrefix("{"), !result.legacyIDs.insert(id).inserted { scan.skipped += 1; return }
            result.observations.append(BluetoothFailureObservation(timestamp: timestamp, severity: severity))
            if let processIdentity {
                if let existing = result.processRanges[processIdentity] {
                    result.processRanges[processIdentity] = BluetoothProcessRange(first: min(existing.first, timestamp), last: max(existing.last, timestamp))
                } else if result.processRanges.count < 64 {
                    result.processRanges[processIdentity] = BluetoothProcessRange(first: timestamp, last: timestamp)
                } else { result.processRangeOverflow = true }
            }
            let candidate = BluetoothCandidate(timestamp: timestamp, severity: severity, id: id)
            if first == nil { first = candidate }
            else if tail.count < eventLimit - 1 { tail.append(candidate) }
            else { tail[tailIndex] = candidate; tailIndex = (tailIndex + 1) % (eventLimit - 1) }
        }
        let description = BluetoothRecord(kind: .hciFailure, title: "Bluetooth HCI failure recorded",
            detail: "bluetoothd explicitly logged an HCI failure, error, timeout, or disallowed command. The original log level is preserved; device identifiers and arbitrary message text are omitted.")
        result.events = ([first].compactMap { $0 } + tail).map { candidate in
            let seconds = Int(candidate.timestamp.timeIntervalSince(wake).rounded())
            return SleepWakeEvent(id: candidate.id, timestamp: candidate.timestamp,
                kind: candidate.severity == .error ? .relatedError : .relatedRecord, severity: candidate.severity,
                title: description.title, detail: description.detail, source: unifiedSource,
                evidence: [commandEvidence, Evidence(source: unifiedSource,
                    detail: "Compact timestamps use the fixed UTC query timezone and millisecond precision; each returned row is counted separately. Details use a fixed privacy-safe description.")],
                correlation: "Recorded \(abs(seconds)) seconds \(seconds < 0 ? "before" : "after") a Wake record. This is temporal proximity only; no causal link to a display symptom is established.",
                bluetoothEvent: .hciFailure)
        }.sorted(by: newestFirst)
        scan.matchedRecordCount = result.observations.count
        scan.coverage = coverage(output, scan: scan, id: sliceID, name: "Bluetooth HCI")
        result.segments = [segment(id: sliceID, kind: "Bluetooth HCI", start: start, end: end, coverage: scan.coverage)]
        return result
    }

    private static func segment(id: String, kind: String, start: Date, end: Date,
                                coverage: LogSourceCoverage) -> FocusedLogSegment {
        FocusedLogSegment(id: id, kind: kind, start: start, end: end,
            coverage: LogSourceCoverage(id: id, name: kind, state: coverage.state,
                detail: coverage.detail, evidence: coverage.evidence))
    }

    private static func focusedCoverage(segments: [FocusedLogSegment], start: Date, end: Date) -> LogSourceCoverage {
        let state: LogCoverageState
        if segments.allSatisfy({ $0.coverage.state == .available }) { state = .available }
        else if segments.allSatisfy({ $0.coverage.state == .unavailable }) { state = .unavailable }
        else { state = .partial }
        let details = segments.map { segment in
            "\(segment.kind) (\(LogTimestamp.display(segment.start)) through \(LogTimestamp.display(segment.end))): \(segment.coverage.state.rawValue). \(segment.coverage.detail)"
        }.joined(separator: " ")
        return LogSourceCoverage(id: "wakeIncidentLog", name: "Latest Wake Incident Window", state: state,
            detail: "Requested interval: \(LogTimestamp.display(start)) through \(LogTimestamp.display(end)). The latest full Wake anchors this interval; Dark Wake is excluded. Each segment has independent completion evidence. \(details) Counts include all recognized returned rows before display sampling; no matching record does not prove successful recovery.",
            evidence: segments.flatMap { $0.coverage.evidence })
    }

    private static func deduplicated(_ events: [SleepWakeEvent]) -> [SleepWakeEvent] {
        var seen = Set<String>()
        return events.sorted(by: newestFirst).compactMap { event in
            let key = identity(event)
            guard seen.insert(key).inserted else { return nil }
            return SleepWakeEvent(id: event.bluetoothEvent == nil ? stableID(key) : event.id,
                timestamp: event.timestamp, kind: event.kind,
                severity: event.severity, title: event.title, detail: event.detail, source: event.source,
                evidence: event.evidence, correlation: event.correlation, bluetoothEvent: event.bluetoothEvent)
        }
    }

    private static func retainingContext(_ unique: [SleepWakeEvent]) -> [SleepWakeEvent] {
        // Preserve explicit Bluetooth lifecycle evidence even when repetitive errors/Faults
        // fill the display. It is necessary to interpret a failure/exit/start sequence.
        let hci = unique.filter { $0.bluetoothEvent == .hciFailure }
        let hciEndpoints = [hci.first, hci.last].compactMap { $0 }
        let lifecycle = unique.filter { $0.bluetoothEvent != nil && $0.bluetoothEvent != .hciFailure }
        var bluetoothIDs = Set<String>()
        let bluetoothContext = Array((hciEndpoints + lifecycle)
            .filter { bluetoothIDs.insert($0.id).inserted }.prefix(50))
        let reservedBluetoothIDs = Set(bluetoothContext.map(\.id))
        let unreservedErrors = unique.filter { $0.severity == .error && !reservedBluetoothIDs.contains($0.id) }
        // Keep independently useful error categories before filling with repetitive HCI
        // errors. Earliest/latest HCI and lifecycle evidence have already been reserved.
        let otherErrors = unreservedErrors.filter { $0.bluetoothEvent != .hciFailure }
        let hciErrors = unreservedErrors.filter { $0.bluetoothEvent == .hciFailure }
        let retainedErrors = Array((otherErrors + hciErrors).prefix(eventLimit - bluetoothContext.count))
        let remaining = eventLimit - retainedErrors.count - bluetoothContext.count
        let powerContext = Array(unique.filter { [.sleep, .wake, .darkWake].contains($0.kind) }.prefix(min(50, remaining)))
        var retainedIDs = Set((retainedErrors + bluetoothContext + powerContext).map(\.id))
        let faults = unique.filter { $0.severity == .fault && !retainedIDs.contains($0.id) }
        let retainedFaults = Array(faults.prefix(max(0, remaining - powerContext.count)))
        retainedIDs.formUnion(retainedFaults.map(\.id))
        let other = unique.filter { retainedIDs.insert($0.id).inserted }
        let capacity = eventLimit - retainedErrors.count - bluetoothContext.count - powerContext.count - retainedFaults.count
        return (retainedErrors + bluetoothContext + powerContext + retainedFaults + Array(other.prefix(max(0, capacity))))
            .sorted(by: newestFirst)
    }

    private struct Scan {
        var events = [SleepWakeEvent]()
        var parsed = 0
        var malformed = 0
        var skipped = 0
        var outsideWindow = 0
        var matchedRecordCount: Int?
        var coverage: LogSourceCoverage
    }

    private static func emptyScan(id: String, name: String) -> Scan {
        Scan(coverage: LogSourceCoverage(id: id, name: name, state: .unavailable,
            detail: "Collection has not been evaluated.", evidence: []))
    }

    // Labels are delimited by two or more spaces. 'Wake Requests' must never become 'Wake'.
    private static let powerLine = try! NSRegularExpression(
        pattern: #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)? [+-]\d{4})[ \t]+(.+?)[ \t]{2,}(.*)$"#)
    private static let relevantPowerLabels: Set<String> = [
        "Sleep", "Wake", "DarkWake", "Sleep Failure", "Wake Failure", "DarkWake Failure",
        "Sleep/Wake Failure", "SleepWakeFailure", "SleepFailure", "WakeFailure", "Failure"
    ]

    private static func parsePower(_ output: CommandOutput, since: Date, until: Date) -> Scan {
        var scan = emptyScan(id: "powerHistory", name: powerSource)
        let timestampParser = LogTimestampParser()
        let commandEvidence = output.evidence
        for rawLine in output.stdout.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = powerLine.firstMatch(in: line, range: range),
                  let timeRange = Range(match.range(at: 1), in: line),
                  let labelRange = Range(match.range(at: 2), in: line),
                  let detailRange = Range(match.range(at: 3), in: line) else {
                if line.first?.isNumber == true || !isPowerHeader(line) { scan.malformed += 1 }
                else { scan.skipped += 1 }
                continue
            }
            let label = String(line[labelRange]).trimmingCharacters(in: .whitespaces)
            // Assertions and request records dominate real pmset output. Exclude them before
            // constructing timestamp formatters; they are never power-event anchors.
            guard relevantPowerLabels.contains(label) else { scan.skipped += 1; continue }
            guard let date = timestampParser.parse(String(line[timeRange])) else { scan.malformed += 1; continue }
            scan.parsed += 1
            guard date >= since, date <= until else { scan.outsideWindow += 1; continue }
            let detail = String(line[detailRange])
            let kind: SleepWakeKind
            let severity: LogSeverity
            let title: String
            switch label {
            case "Sleep", "Wake", "DarkWake":
                if hasFailureSignature(detail) {
                    kind = .failure; severity = .error; title = "Logged sleep/wake failure"
                } else {
                    kind = label == "Sleep" ? .sleep : label == "Wake" ? .wake : .darkWake
                    severity = .information; title = kind.rawValue + " recorded"
                }
            case "Sleep Failure", "Wake Failure", "DarkWake Failure", "Sleep/Wake Failure", "SleepWakeFailure", "SleepFailure", "WakeFailure":
                guard !isOnlyBenignFailureText(detail) else { scan.skipped += 1; continue }
                kind = .failure; severity = .error; title = "Logged sleep/wake failure"
            case "Failure":
                guard hasFailureSignature(detail) else { scan.skipped += 1; continue }
                kind = .failure; severity = .error; title = "Logged sleep/wake failure"
            default:
                scan.skipped += 1; continue
            }
            scan.events.append(event(date, kind: kind, severity: severity, title: title,
                detail: detail, source: powerSource, commandEvidence: commandEvidence))
        }
        scan.coverage = coverage(output, scan: scan, id: "powerHistory", name: powerSource)
        return scan
    }

    private static func isPowerHeader(_ line: String) -> Bool {
        ["Time stamp", "Timestamp", "UUID", "Sleep/Wakes since boot", "Total Sleep/Wakes since boot",
         "Total Sleep", "Total Wake", "Total DarkWake", "Start", "End"].contains { line.hasPrefix($0) }
    }

    private static func parseUnified(_ output: CommandOutput, anchors: [Date], wakeAnchors: [Date], since: Date, until: Date) -> Scan {
        var scan = emptyScan(id: "sleepWakeLog", name: unifiedSource)
        let timestampParser = LogTimestampParser()
        let commandEvidence = output.evidence
        for rawLine in output.stdout.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8),
                  let dictionary = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                scan.malformed += 1; continue
            }
            // log show emits a final count/finished object in NDJSON mode. It is metadata.
            if Set(dictionary.keys) == Set(["count", "finished"]),
               let count = dictionary["count"] as? Int, count >= 0,
               dictionary["finished"] as? Bool == true {
                scan.skipped += 1; continue
            }
            guard let rawTime = dictionary["timestamp"] as? String,
                  let timestamp = timestampParser.parse(rawTime),
                  let message = dictionary["eventMessage"] as? String else { scan.malformed += 1; continue }
            scan.parsed += 1
            guard timestamp >= since, timestamp <= until else { scan.outsideWindow += 1; continue }
            // A sandbox denial involving a process named /bin/sleep is not a power transition.
            guard !message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("sandbox:") else {
                scan.skipped += 1; continue
            }
            let type = (dictionary["messageType"] as? String)?.lowercased() ?? ""
            let typedError = type == "error"
            let typedFault = type == "fault"
            // Process paths are classification inputs only and never enter a result.
            let processName = (dictionary["processImagePath"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
            if processName == "bluetoothd" || processName == "launchd" {
                if let bluetooth = bluetoothRecord(message, process: processName),
                   let wake = wakeAnchors.filter({ timestamp >= $0.addingTimeInterval(-300) && timestamp <= $0.addingTimeInterval(120) })
                    .min(by: { abs($0.timeIntervalSince(timestamp)) < abs($1.timeIntervalSince(timestamp)) }) {
                    let seconds = Int(timestamp.timeIntervalSince(wake).rounded())
                    let position = seconds < 0 ? "before" : "after"
                    scan.events.append(event(timestamp, kind: typedError ? .relatedError : .relatedRecord,
                        severity: sourceSeverity(type), title: bluetooth.title, detail: bluetooth.detail,
                        source: unifiedSource, commandEvidence: commandEvidence,
                        correlation: "Recorded \(abs(seconds)) seconds \(position) a Wake record. This is temporal proximity only; a daemon lifecycle sequence does not prove the cause of a display problem or successful Bluetooth recovery.",
                        bluetoothEvent: bluetooth.kind,
                        identitySeed: [rawTime, processName, message, type].joined(separator: "\u{1f}")))
                } else { scan.skipped += 1 }
                // Unrelated launchd and routine Bluetooth messages are outside this scope.
                continue
            }
            let signature = hasFailureSignature(message)
            guard !isOnlyBenignFailureText(message) else { scan.skipped += 1; continue }
            let sleepRelated = matches(message, #"(?i)\b(?:sleep|wake|darkwake|sleepwake|sleeping|waking|resume)\b"#)
            if matches(message, #"(?i)\bnot entitled to set (?:the )?wake reason\b"#) {
                let severity: LogSeverity = typedError ? .error : typedFault ? .fault : type == "warning" ? .warning : .information
                scan.events.append(event(timestamp, kind: typedError ? .relatedError : .relatedRecord,
                    severity: severity, title: "Wake-reason API permission error",
                    detail: message, source: unifiedSource, commandEvidence: commandEvidence,
                    correlation: "The caller lacked permission to set a wake reason. This API permission error does not establish that a sleep or wake transition failed; the source log severity is preserved."))
                continue
            }
            if matches(message, #"(?i)\bfailed to get (?:the )?(?:sleep|wake) type\b"#) {
                let severity: LogSeverity = typedError ? .error : typedFault ? .fault : .warning
                scan.events.append(event(timestamp, kind: typedError ? .relatedError : .relatedRecord,
                    severity: severity, title: typedError ? "Sleep/wake diagnostic query error" : "Sleep/wake diagnostic query failed",
                    detail: message, source: unifiedSource, commandEvidence: commandEvidence,
                    correlation: "A query for diagnostic information failed. This does not establish that a sleep or wake transition failed, or identify the cause of a user-visible problem."))
                continue
            }
            if signature || ((typedError || typedFault) && sleepRelated) {
                let faultOnly = typedFault && !signature
                scan.events.append(event(timestamp,
                    kind: signature ? .failure : faultOnly ? .relatedRecord : .relatedError,
                    severity: faultOnly ? .fault : .error,
                    title: signature ? "Logged sleep/wake failure" : faultOnly ? "Fault-level sleep/wake record" : "Sleep/wake error recorded",
                    detail: message, source: unifiedSource, commandEvidence: commandEvidence,
                    correlation: faultOnly ? "The source logged this record at Fault level. That level alone does not establish a failed transition or current malfunction." : nil))
                continue
            }
            let graphics = matches(message + " " + processName,
                #"(?i)\b(?:gpu|graphics|iographics\w*|iogpu\w*|ioframebuffer\w*|framebuffer|ioacceldisplaypipe\w*|amd\w*|radeon|nvidia|display|windowserver|accelerator)\b"#)
            let peripheral = matches(message, #"(?i)\bappleusb\w*\b"#) &&
                matches(message, #"(?i)\b(?:display|isight|audio|cinema)\b"#)
            guard typedError || typedFault, graphics || peripheral,
                  let anchor = anchors.min(by: { abs($0.timeIntervalSince(timestamp)) < abs($1.timeIntervalSince(timestamp)) }),
                  abs(anchor.timeIntervalSince(timestamp)) <= 120 else { scan.skipped += 1; continue }
            let seconds = Int(abs(anchor.timeIntervalSince(timestamp)).rounded())
            let title = typedFault
                ? (peripheral ? "Fault-level display peripheral record near a power event" : "Fault-level graphics record near a power event")
                : (peripheral ? "Display peripheral error near a power event" : "Graphics error near a power event")
            let faultCaveat = typedFault ? " The source logged this at Fault level; that level alone does not prove a graphics failure or current malfunction." : ""
            scan.events.append(event(timestamp, kind: typedFault ? .relatedRecord : .relatedError,
                severity: typedFault ? .fault : .error, title: title, detail: message, source: unifiedSource, commandEvidence: commandEvidence,
                correlation: "Recorded within \(seconds) seconds of a sleep/wake event. This is temporal proximity only; no causal link or successful desktop recovery is established." + faultCaveat))
        }
        scan.coverage = coverage(output, scan: scan, id: "sleepWakeLog", name: unifiedSource)
        return scan
    }

    private static let benignFailurePatterns = [
            #"(?i)\bno\s+(?:sleep[ /_-]*wake|sleep|wake|resume)\s+failure(?:\s+string)?\b"#,
            #"(?i)\b(?:no|zero)\s+(?:errors?|failures?|faults?|timeouts?)\b"#,
            #"(?i)\b(?:errors?|failures?|failed|faults?|timeouts?)(?:\s+count)?\s*[:=]\s*(?:0x0+|0+)\b"#,
            #"(?i)\b(?:errors?|failures?|faults?)\s*[:=]\s*(?:none|false)\b"#
        ].map { try! NSRegularExpression(pattern: $0) }

    private static func strippedBenignText(_ text: String) -> String {
        let lower = text.lowercased()
        guard lower.contains("no ") || lower.contains("zero ") || lower.contains(":") || lower.contains("=") else { return text }
        return benignFailurePatterns.reduce(text) { value, pattern in
            pattern.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value), withTemplate: "")
        }
    }

    private struct BluetoothRecord {
        let kind: BluetoothEventKind
        let title: String
        let detail: String
    }

    private static func sourceSeverity(_ type: String) -> LogSeverity {
        switch type {
        case "error": return .error
        case "fault": return .fault
        case "warning": return .warning
        default: return .information
        }
    }

    private static func bluetoothRecord(_ message: String, process: String) -> BluetoothRecord? {
        if process == "launchd" {
            // Match the exact service, not a similarly named helper or an unrelated daemon.
            guard matches(message, #"(?i)(?:^|[\s/\[])com\.apple\.bluetoothd(?=$|[\s\[\]:()/])"#) else { return nil }
            if matches(message, #"(?i)\bexited\b|\b(?:service\s+)?state\s*[:=]\s*exited\b"#) {
                return BluetoothRecord(kind: .daemonExit, title: "Bluetooth daemon exit recorded",
                    detail: "launchd recorded an exit of com.apple.bluetoothd. An exit alone does not establish a crash or its cause.")
            }
            if matches(message, #"(?i)\bspawned with pid\b|\b(?:service\s+)?state\s*[:=]\s*running\b"#) {
                return BluetoothRecord(kind: .daemonStart, title: "Bluetooth daemon start recorded",
                    detail: "launchd recorded com.apple.bluetoothd as spawned or running. This does not establish that Bluetooth devices reconnected.")
            }
            return nil
        }
        guard process == "bluetoothd", !isOnlyBenignFailureText(message) else { return nil }
        let value = strippedBenignText(message)
        if matches(value, #"(?i)\bhci(?:controller|transport|command)?\b"#),
           matches(value, #"(?i)\b(?:failed|failure|error|timeout|timed out|command disallowed)\b"#) {
            return BluetoothRecord(kind: .hciFailure, title: "Bluetooth HCI failure recorded",
                detail: "bluetoothd explicitly logged an HCI failure, error, timeout, or disallowed command. The original log level is preserved; device identifiers and arbitrary message text are omitted.")
        }
        if matches(value, #"(?i)\bcontroller(?:\s+state)?\s*[:=-]?\s+(?:is\s+)?(?:ready|initialized)\b|\b(?:controller|hci)\s+initiali[sz]ation\s+(?:complete|completed|succeeded)\b"#) {
            return BluetoothRecord(kind: .controllerReady, title: "Bluetooth controller readiness recorded",
                detail: "bluetoothd reported controller readiness or completed initialization. This does not establish that a particular device or the desktop recovered.")
        }
        return nil
    }

    private static func isOnlyBenignFailureText(_ text: String) -> Bool {
        let stripped = strippedBenignText(text)
        return stripped != text && !matches(stripped,
            #"(?i)\b(?:error|fault|fail(?:ed|ure)?|timeout|timed out|hang|stalled|refused|aborted|unable)\b"#)
    }

    private static func hasFailureSignature(_ text: String) -> Bool {
        let value = strippedBenignText(text)
        let patterns = [
            #"(?i)\bsleep[ /_-]*wake\s+(?:failure|failed|hang|hung|timeout|timed out)\b"#,
            #"(?i)\b(?:sleep|wake|darkwake|resume)(?:\s+transition)?\s*[:=-]?\s+(?:failure|failed|timeout|timed out|hang|hung|stalled|refused|aborted)\b"#,
            #"(?i)\b(?:failure|failed|timeout|timed out|hang|hung)\s+(?:during|while|on|in|to)\s+(?:the\s+)?(?:sleep|wake|darkwake|resume)(?:\s+transition)?\b"#,
            #"(?i)\b(?:failed|failure)\s+(?:sleep|wake|darkwake|resume)\s+transition\b"#
        ]
        return patterns.contains { matches(value, $0) }
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func event(_ timestamp: Date, kind: SleepWakeKind, severity: LogSeverity, title: String,
                              detail: String, source: String, commandEvidence: Evidence, correlation: String? = nil,
                              bluetoothEvent: BluetoothEventKind? = nil, identitySeed: String? = nil) -> SleepWakeEvent {
        // Bluetooth details are fixed descriptions produced above, with no raw message fields.
        let excerpt = bluetoothEvent == nil ? String(LogRedactor.sanitize(detail).prefix(600)) : String(detail.prefix(600))
        return SleepWakeEvent(id: identitySeed.map(stableID) ?? "pending", timestamp: timestamp, kind: kind, severity: severity, title: title,
            detail: excerpt.isEmpty ? "Details unavailable after privacy filtering." : excerpt,
            source: source, evidence: [commandEvidence,
                Evidence(source: source, detail: "Record timestamp parsed with its explicit timezone; excerpt privacy-filtered and limited to 600 characters.")],
            correlation: correlation, bluetoothEvent: bluetoothEvent)
    }

    private static func coverage(_ output: CommandOutput, scan: Scan, id: String, name: String) -> LogSourceCoverage {
        let incomplete = !output.succeeded || output.outputWasTruncated || scan.malformed > 0
        let state: LogCoverageState
        if !output.succeeded && scan.parsed == 0 { state = .unavailable }
        else if scan.malformed > 0 && scan.parsed == 0 { state = .unavailable }
        else { state = incomplete ? .partial : .available }
        let detail = "Parsed records: \(scan.parsed); matches before deduplication and display limits: \(scan.matchedRecordCount ?? scan.events.count); skipped outside scope: \(scan.skipped); outside requested window: \(scan.outsideWindow); malformed or unrecognized lines: \(scan.malformed). Termination: \(output.termination.rawValue); exit: \(output.exitCode.map(String.init) ?? "unavailable"); output truncated: \(output.outputWasTruncated). Retention and access may hide events. No matching record does not prove successful sleep or resume."
        return LogSourceCoverage(id: id, name: name, state: state, detail: detail, evidence: [output.evidence])
    }

    private static func combinedUnifiedCoverage(historical: LogSourceCoverage, recent: LogSourceCoverage) -> LogSourceCoverage {
        let state = combinedState(historical.state, recent.state)
        return LogSourceCoverage(id: "sleepWakeLog", name: unifiedSource, state: state,
            detail: "Historical query (last seven days): \(historical.state.rawValue). \(historical.detail) Recent query (last two hours): \(recent.state.rawValue). \(recent.detail) Matching records from the two queries are merged without double-counting identical records; a successful recent query does not fill gaps in historical coverage.",
            evidence: historical.evidence + recent.evidence)
    }

    private static func combinedState(_ first: LogCoverageState, _ second: LogCoverageState) -> LogCoverageState {
        if first == .available && second == .available { return .available }
        if first == .unavailable && second == .unavailable { return .unavailable }
        return .partial
    }

    private static func newestFirst(_ lhs: SleepWakeEvent, _ rhs: SleepWakeEvent) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
        return identity(lhs) < identity(rhs)
    }

    private static func identity(_ event: SleepWakeEvent) -> String {
        // Fixed privacy-safe Bluetooth descriptions can represent distinct raw records at
        // the same timestamp. Their opaque IDs preserve that distinction across queries.
        if event.bluetoothEvent != nil { return event.source + "\u{1f}" + event.id }
        return event.source + "\u{1f}" + String(event.timestamp.timeIntervalSince1970) + "\u{1f}" + event.detail
    }

    private static func stableID(_ key: String) -> String {
        let hash = key.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        return "sleep-wake-" + String(hash, radix: 16)
    }
}
