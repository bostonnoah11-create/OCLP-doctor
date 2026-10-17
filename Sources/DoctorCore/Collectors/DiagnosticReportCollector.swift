import Foundation

public struct DiagnosticReportScan: Sendable {
    public let events: [SleepWakeEvent]
    public let coverage: LogSourceCoverage
    public init(events: [SleepWakeEvent], coverage: LogSourceCoverage) {
        self.events = events; self.coverage = coverage
    }
}

public struct DiagnosticReportCollector: Sendable {
    private let reader: any DiagnosticReportReading
    public init(reader: any DiagnosticReportReading = LocalDiagnosticReportReader()) { self.reader = reader }

    public func collect(since: Date, until: Date) async -> DiagnosticReportScan {
        guard since <= until else {
            return DiagnosticReportScan(events: [], coverage: LogSourceCoverage(id: "diagnosticReports", name: "Diagnostic Reports",
                state: .unavailable, detail: "Invalid requested time window.", evidence: []))
        }
        let batch = reader.read(since: since, until: until)
        var events = [SleepWakeEvent]()
        var malformed = 0
        var extraLimited = max(0, batch.documents.count - 40)
        var extraOversized = 0
        var bytes = 0
        var parsed = 0
        for (index, document) in batch.documents.prefix(40).enumerated() {
            if document.data.count > 1_048_576 { extraOversized += 1; continue }
            guard bytes + document.data.count <= 8_388_608 else { extraLimited += 1; continue }
            bytes += document.data.count
            switch Self.parse(document.data) {
            case .invalid: malformed += 1
            case .unrelated: parsed += 1
            case .failure(let timestamp, let signature, let seconds):
                parsed += 1
                guard timestamp >= since, timestamp <= until else { continue }
                // Only fixed signatures and parsed integers leave the reader. Never raw report text.
                let suffix = seconds.map { " Reported timeout: \($0) seconds." } ?? ""
                let source = document.location.label
                events.append(SleepWakeEvent(id: "diagnostic-report-\(index)-\(Int(timestamp.timeIntervalSince1970))",
                    timestamp: timestamp, kind: .failure, severity: .error, title: signature,
                    detail: "The report explicitly records this sleep/wake failure. Its recorded timestamp may differ from the start of the failed transition; the underlying cause is unconfirmed." + suffix,
                    source: source, evidence: [Evidence(source: source + " · report \(index + 1)",
                        detail: "Matched an explicit failure signature and an in-report timestamp with timezone. File modification time was not used as event time.")]))
            }
        }
        let limited = batch.limitedFiles + extraLimited
        let oversized = batch.oversizedFiles + extraOversized
        let incomplete = batch.missingDirectories > 0 || batch.unreadableDirectories > 0 || batch.unreadableFiles > 0 ||
            oversized > 0 || limited > 0 || malformed > 0 || batch.enumerationLimited
        let state: LogCoverageState = batch.readableDirectories == 0 ? .unavailable : incomplete ? .partial : .available
        let detail = "Directories read: \(batch.readableDirectories)/2; missing: \(batch.missingDirectories); inaccessible: \(batch.unreadableDirectories). Candidates: \(batch.candidateCount); parsed: \(parsed); malformed or missing reliable timestamp: \(malformed); unreadable: \(batch.unreadableFiles); oversized: \(oversized); bounded out: \(limited); directory listing limited: \(batch.enumerationLimited). No matching report does not prove successful sleep or resume."
        return DiagnosticReportScan(events: events.sorted { $0.timestamp > $1.timestamp },
            coverage: LogSourceCoverage(id: "diagnosticReports", name: "Diagnostic Reports", state: state,
                detail: detail, evidence: [Evidence(source: "System and current-user DiagnosticReports directories",
                    detail: "Top-level only; 40 newest candidates; 1 MiB per report; 8 MiB total; \(bytes) bytes inspected. Filenames and raw report content are not exported.")]))
    }

    private enum ParsedReport {
        case invalid, unrelated
        case failure(Date, String, Int?)
    }

    private static func parse(_ data: Data) -> ParsedReport {
        guard let text = String(data: data, encoding: .utf8) else { return .invalid }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            guard let objects = jsonObjects(trimmed), !objects.isEmpty else { return .invalid }
            let body = objects.last ?? [:]
            let header = objects.first ?? [:]
            let messages = ["panicString", "reason", "event", "failureReason"].compactMap { body[$0] as? String }
            guard let match = messages.compactMap(signature).first else { return .unrelated }
            let dates = [body["date"], body["captureTime"], body["timestamp"], header["timestamp"]].compactMap { $0 as? String }
            guard let date = dates.compactMap(parseTimestamp).first else { return .invalid }
            return .failure(date, match.0, match.1)
        }
        guard let match = signature(text) else { return .unrelated }
        let regex = try! NSRegularExpression(pattern: #"(?m)^(?:Date/Time|Date):[ \t]*([^\r\n]+)"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let timestamps = regex.matches(in: text, range: range).compactMap { result -> String? in
            guard let range = Range(result.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
        guard let date = timestamps.compactMap(parseTimestamp).first else { return .invalid }
        return .failure(date, match.0, match.1)
    }

    private static func signature(_ text: String) -> (String, Int?)? {
        // Match the failure line, not arbitrary paths, diagnostic code, or quoted backtraces.
        let prefix = #"(?im)^(?:panic\([^\r\n]{0,200}\):[ \t]*|(?:Event|Reason|Failure Reason):[ \t]*)?"#
        let signatures = [
            (#"Sleep Wake failure in EFI\b"#, "Sleep Wake failure in EFI"),
            (#"Sleep/Wake hang(?: detected)?\b"#, "Sleep/Wake hang detected"),
            (#"Sleep transition timed out(?: after ([0-9]{1,8}) seconds)?\b"#, "Sleep transition timed out"),
            (#"Wake transition timed out(?: after ([0-9]{1,8}) seconds)?\b"#, "Wake transition timed out")
        ]
        for (pattern, title) in signatures {
            let regex = try! NSRegularExpression(pattern: prefix + pattern)
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
                let seconds: Int?
                if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) { seconds = Int(text[range]) }
                else { seconds = nil }
                return (title, seconds)
            }
        }
        return nil
    }

    static func parseTimestamp(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?\s*(?:Z|[+-]\d{2}:?\d{2})$"#, options: .regularExpression) != nil else { return nil }
        var normalized = value.replacingOccurrences(of: " ", with: "")
        if !normalized.contains("T") { normalized.insert("T", at: normalized.index(normalized.startIndex, offsetBy: 10)) }
        if normalized.range(of: #"[+-]\d{4}$"#, options: .regularExpression) != nil {
            normalized.insert(":", at: normalized.index(normalized.endIndex, offsetBy: -2))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: normalized) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: normalized)
    }

    /// Apple IPS uses a JSON metadata object followed by a JSON report object.
    private static func jsonObjects(_ text: String) -> [[String: Any]]? {
        let bytes = Array(text.utf8)
        var depth = 0, start = 0
        var inString = false, escaped = false
        var objects = [[String: Any]]()
        for (index, byte) in bytes.enumerated() {
            if depth == 0 {
                if [9, 10, 13, 32].contains(byte) { continue }
                guard byte == 123, objects.count < 2 else { return nil }
                start = index; depth = 1; continue
            }
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
            } else if byte == 34 { inString = true }
            else if byte == 123 { depth += 1 }
            else if byte == 125 {
                depth -= 1
                if depth == 0 {
                    guard let object = (try? JSONSerialization.jsonObject(with: Data(bytes[start...index]))) as? [String: Any] else { return nil }
                    objects.append(object)
                }
            }
        }
        return depth == 0 && !inString ? objects : nil
    }
}
