import Foundation

public enum LogTimestamp {
    /// Reject timestamps without a timezone instead of silently assigning a local zone.
    public static func parse(_ text: String) -> Date? {
        LogTimestampParser().parse(text)
    }

    public static func display(_ date: Date, fractionalSeconds: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = fractionalSeconds ? "yyyy-MM-dd HH:mm:ss.SSS Z" : "yyyy-MM-dd HH:mm:ss Z"
        return formatter.string(from: date)
    }

    /// Encode milliseconds without truncating a binary floating-point .673 to .672.
    public static func iso8601Milliseconds(_ date: Date) -> String {
        let total = (date.timeIntervalSince1970 * 1_000).rounded()
        let seconds = floor(total / 1_000)
        let milliseconds = Int(total - seconds * 1_000)
        let whole = Date(timeIntervalSince1970: seconds).ISO8601Format()
        return String(whole.dropLast()) + String(format: ".%03dZ", milliseconds)
    }
}

/// Reuse within one synchronous parsing pass. Each pass owns its formatters;
/// this mutable Foundation state must not be shared between concurrent scans.
final class LogTimestampParser {
    private let fractionalISO: ISO8601DateFormatter
    private let wholeISO: ISO8601DateFormatter
    private let formatters: [DateFormatter]

    init() {
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractionalISO = fractionalISO
        let wholeISO = ISO8601DateFormatter()
        wholeISO.formatOptions = [.withInternetDateTime]
        self.wholeISO = wholeISO
        formatters = ["yyyy-MM-dd HH:mm:ss.SSSSSSZ", "yyyy-MM-dd HH:mm:ss.SSSZ", "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss.SSS Z", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.isLenient = false
            formatter.dateFormat = format
            return formatter
        }
    }

    func parse(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 80 else { return nil }
        if let date = fractionalISO.date(from: value) { return date }
        if let date = wholeISO.date(from: value) { return date }
        guard value.range(of: #"(Z|[+-][0-9]{2}:?[0-9]{2})$"#, options: .regularExpression) != nil else { return nil }
        for formatter in formatters {
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

public enum LogRedactor {
    /// Log messages are evidence, never instructions. Export only bounded, redacted text.
    public static func sanitize(_ text: String) -> String {
        var result = String(text.prefix(4096))
        let rules: [(String, String)] = [
            (#"(?i)\b(?:IOPlatformSerialNumber|serial[ _-]*number|serial|uuid|user[ _-]*name|user|account|host[ _-]*name|ssid|password|token)\s*[:=]\s*(?:\"[^\"]*(?:\"|$)|'[^']*(?:'|$)|[^\s,;]+)"#, "[identifier redacted]"),
            (#"(?i)\b(?:pid|processID|threadID|tid)\s*[:=]?\s*[0-9]+\b"#, "[process identifier redacted]"),
            (#"(?i)^\s*\[[0-9]+\](?=\s+is not entitled\b)"#, "[process identifier redacted]"),
            (#"\b([A-Za-z_][A-Za-z0-9_.-]*)\([0-9]{2,}\)"#, "$1([process identifier redacted])"),
            (#"(?i)\b0x[0-9a-f]{12,16}\b"#, "[address redacted]"),
            (#"(?i)\b(?:https?|file)://[^\s\"<>]+"#, "[URL redacted]"),
            (#"[\"']/(?:Users|Volumes|private|var|Library|System|tmp)/[^\"']*(?:[\"']|$)"#, "[path redacted]"),
            (#"(?:/Users/|/Volumes/|/private/|/var/|/Library/|/System/|/tmp/)[^\s\"<>]*"#, "[path redacted]"),
            (#"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#, "[UUID redacted]"),
            (#"(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b"#, "[MAC redacted]"),
            (#"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b"#, "[IP redacted]"),
            (#"(?i)\b[0-9a-f]{0,4}:[0-9a-f:]{2,}(?:%[a-z0-9]+)?\b"#, "[address redacted]"),
            (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[email redacted]"),
            (#"(?i)\b[^\s\"<>]+\.local\b"#, "[host redacted]")
        ]
        for (pattern, replacement) in rules {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        result = result.components(separatedBy: .controlCharacters).filter { !$0.isEmpty }.joined(separator: " ")
        return String(result.prefix(600))
    }
}
