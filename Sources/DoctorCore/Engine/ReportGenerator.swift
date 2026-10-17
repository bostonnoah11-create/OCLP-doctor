import Foundation

public enum ReportGenerator {
    public static func generate(_ snapshot: SystemInfo) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "OCLP Doctor — Beta 0.5.1",
            "Independent, unofficial project · Read-only diagnostics",
            "Scan started: \(formatter.string(from: snapshot.capturedAt))",
            String(format: "Collection time: %.2f seconds", snapshot.duration),
            snapshot.isDemo ? "Data: DEMO / synthetic fixtures (not a diagnosis of this Mac)" : "Data: local system observations",
            "Healthy confirms an individual observation, not the health of the entire Mac.",
            "Unknown means insufficient evidence. Reduced SIP and patch records alone do not establish a fault or successful patching.",
            "Hardware identifier fields, complete NVRAM and raw diagnostic reports are excluded. Log excerpts use bounded, best-effort privacy filtering; review them before sharing.",
            ""
        ]
        let review = snapshot.issueReview
        lines.append("[Needs your attention]")
        lines.append("Official catalog reviewed: \(review.reviewedOn). Bundled offline references, not a live or exhaustive issue database.")
        lines.append("Recorded problems precede compatibility reviews and evidence gaps. Neither a hardware match nor an error timestamp proves a cause or current failure.")
        lines.append("")
        for finding in review.findings {
            lines.append("• \(line(finding.title)) [\(finding.kind.rawValue); \(finding.priority.rawValue) priority]")
            lines.append("  \(line(finding.detail))")
            for evidence in finding.evidence { lines.append("  Evidence: \(line(evidence.source)) — \(line(evidence.detail))") }
            for step in finding.nextSteps { lines.append("  Suggested check: \(line(step))") }
            for source in finding.sources { lines.append("  Official source: \(line(source.title)) — \(line(source.url))") }
            lines.append("")
        }
        for section in snapshot.sections {
            lines.append("[\(line(section.title))]")
            for item in section.items {
                lines.append("• \(line(item.label)): \(line(item.displayValue)) [\(item.status.rawValue)]")
                lines.append("  Interpretation: \(line(item.message))")
                for evidence in item.evidence {
                    lines.append("  Evidence: \(line(evidence.source)) — \(line(evidence.detail))")
                }
            }
            lines.append("")
        }
        lines.append("[Official issue catalog]")
        lines.append("Reviewed \(review.reviewedOn); \(review.catalog.count) curated entries. Upstream state may have changed. Entries are references, not diagnoses of this Mac.")
        lines.append("")
        for issue in review.catalog {
            lines.append("• \(line(issue.project)) · \(line(issue.title))")
            lines.append("  State at review: \(line(issue.upstreamStatus))")
            lines.append("  \(line(issue.summary))")
            lines.append("  Scope: \(line(issue.scope))")
            for step in issue.nextSteps { lines.append("  Suggested check: \(line(step))") }
            for source in issue.sources { lines.append("  Official source: \(line(source.title)) — \(line(source.url))") }
            lines.append("")
        }
        if let sleepWake = snapshot.sleepWake {
            lines.append(sleepWakeReport(sleepWake))
        }
        lines.append("This report is not sent automatically. Review its contents before sharing.")
        return lines.joined(separator: "\n")
    }

    public static func sleepWakeReport(_ report: SleepWakeReport) -> String {
        var lines = [
            "[Sleep & Wake timeline]",
            "Requested window: \(LogTimestamp.display(report.windowStart)) → \(LogTimestamp.display(report.windowEnd))",
            "Timezone: \(TimeZone.current.identifier); each timestamp includes its UTC offset.",
            "A Fault log level alone does not establish failure. Some graphics drivers emit completed-operation traces at this level.",
            "Records from different sources may refer to the same incident. Counts are not unique incidents.",
            "A wake entry does not prove the display was usable. No matching error does not rule out brief visual artifacts or other resume problems.",
            "Timing is correlation only; the root cause and current impact are unconfirmed.", ""
        ]
        lines.append("Error categories in retained history (mutually exclusive record counts):")
        if report.errorGroups.isEmpty { lines.append("No Error-level records in the retained evidence. This is not a no-failure verdict.") }
        for group in report.errorGroups {
            lines.append("• \(group.title): \(group.count) records; latest \(LogTimestamp.display(group.latestAt)). \(group.interpretation)")
        }
        lines.append("Total Error-level records: \(report.errorCount). Fault-level records: \(report.faultCount). Warning records: \(report.warningCount). Omitted records: \(report.omittedEventCount).")
        lines.append("")
        if let focused = report.focusedWake {
            lines.append("[Latest wake — focused evidence]")
            lines.append("Wake: \(LogTimestamp.display(focused.wakeAt))")
            lines.append("Focused window: \(LogTimestamp.display(focused.start)) → \(LogTimestamp.display(focused.end))")
            lines.append("Focused counts are a separate view of overlapping evidence; do not add them to history totals.")
            if let summary = focused.scanSummary, focused.bluetoothSummary.countsAreFromFullScan {
                lines.append("Analyzed matches before display sampling: \(summary.matchedEventCount). Displayed evidence rows: \(focused.events.count). Counts below include all collected matches, even when the event list is sampled. Query coverage determines whether collection completed.")
            }
            for group in focused.errorGroups { lines.append("• \(group.title): \(group.count) Error-level records; latest \(LogTimestamp.display(group.latestAt))") }
            let bluetooth = focused.bluetoothSummary
            lines.append("Bluetooth: \(bluetooth.title)")
            lines.append(bluetooth.detail)
            for event in bluetooth.sequence {
                lines.append("\(LogTimestamp.display(event.timestamp, fractionalSeconds: event.bluetoothEvent != nil)) [\(event.severity.rawValue)] \(line(event.title)) — \(line(event.detail))")
            }
            if bluetooth.sequenceOmittedEventCount > 0 {
                lines.append("Bluetooth sequence is sampled; \(bluetooth.sequenceOmittedEventCount) additional records are included in the analysis counts.")
            }
            lines.append("Focused coverage: \(focused.coverage.state.rawValue); records not displayed: \(focused.omittedEventCount). \(line(focused.coverage.detail))")
            for segment in focused.segments ?? [] {
                lines.append("Query segment: \(line(segment.kind)) · \(LogTimestamp.display(segment.start)) → \(LogTimestamp.display(segment.end)) [\(segment.coverage.state.rawValue)]")
                lines.append("  \(line(segment.coverage.detail))")
            }
            for evidence in focused.coverage.evidence { lines.append("Evidence: \(line(evidence.source)) — \(line(evidence.detail))") }
            lines.append("")
        } else {
            lines.append("Latest-wake focused evidence is unavailable; no focused recovery or recurrence conclusion is possible.")
            lines.append("")
        }
        for source in report.sources {
            lines.append("Source: \(line(source.name)) [\(source.state.rawValue)]")
            lines.append("  \(line(source.detail))")
            for evidence in source.evidence {
                lines.append("  Evidence: \(line(evidence.source)) — \(line(evidence.detail))")
            }
        }
        lines.append("")
        if report.events.isEmpty { lines.append("No matching records in the collected evidence. This is not a successful-resume verdict.") }
        let sharedEvidence = report.sources.flatMap(\.evidence) + (report.focusedWake?.coverage.evidence ?? [])
        for event in report.events.sorted(by: { $0.timestamp > $1.timestamp }) {
            lines.append("\(LogTimestamp.display(event.timestamp, fractionalSeconds: event.bluetoothEvent != nil)) [\(event.severity.rawValue)] \(line(event.title))")
            lines.append("  Type: \(event.kind.rawValue); source: \(line(event.source))")
            lines.append("  \(line(event.detail))")
            if let correlation = event.correlation { lines.append("  Timing: \(line(correlation))") }
            // Source commands are documented above once, rather than hundreds of times.
            for evidence in event.evidence where !sharedEvidence.contains(evidence) {
                lines.append("  Evidence: \(line(evidence.source)) — \(line(evidence.detail))")
            }
            lines.append("")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    // Prevent raw control characters/newlines in source strings from impersonating report fields.
    private static func line(_ text: String) -> String {
        text.components(separatedBy: .controlCharacters).joined(separator: " ")
    }
}
