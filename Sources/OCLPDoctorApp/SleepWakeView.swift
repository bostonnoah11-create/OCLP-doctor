import DoctorCore
import SwiftUI

private enum EventFilter: String, CaseIterable, Identifiable {
    case all = "All events"
    case errors = "Errors"
    case faults = "Faults"
    case warnings = "Warnings"
    var id: String { rawValue }

    func includes(_ event: SleepWakeEvent) -> Bool {
        switch self {
        case .all: return true
        case .errors: return event.severity == .error
        case .faults: return event.severity == .fault
        case .warnings: return event.severity == .warning
        }
    }
}

struct SleepWakeView: View {
    let report: SleepWakeReport
    @State private var filter: EventFilter = .all

    private var visibleEvents: [SleepWakeEvent] {
        report.events.filter(filter.includes).sorted { $0.timestamp > $1.timestamp }
    }

    private var aggregateCoverage: LogCoverageState {
        if report.sources.isEmpty || report.sources.allSatisfy({ $0.state == .unavailable }) {
            return .unavailable
        }
        return report.hasIncompleteCoverage ? .partial : .available
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ErrorCategoryOverview(groups: report.errorGroups)
            if let focus = report.focusedWake {
                FocusedWakeView(focus: focus)
            } else {
                InfoNotice(title: "Focused wake window unavailable", message: "A recent wake anchor or focused log window could not be established. This does not confirm a successful wake or the absence of Bluetooth failures.", icon: "questionmark.circle")
            }
            SectionHeading(title: "Aggregate history", subtitle: "Retained records across the requested seven-day window.")
            summary
            InfoNotice(
                title: "How to read these records",
                message: "Fault is a log level, not a confirmed failure; some Fault records describe completed work. A wake entry does not confirm a usable desktop, and no matching errors does not prove a successful wake. Nearby records do not establish a cause.",
                icon: "info.circle"
            )
            DisclosureGroup {
                coverage.padding(.top, 14)
            } label: {
                Label("Source coverage & collection limits", systemImage: "tray.full")
                    .font(.system(size: 13, weight: .semibold))
            }
            timeline
        }
    }

    private var summary: some View {
        DoctorCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 20) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 29, weight: .light))
                        .foregroundColor(DoctorStyle.blue)
                        .frame(width: 58, height: 58)
                        .background(DoctorStyle.blue.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Last 7 days").font(.system(size: 20, weight: .semibold))
                        Text("\(report.events.count) collected events")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                        if report.omittedEventCount > 0 {
                            Text("\(report.omittedEventCount) additional records omitted by the display limit")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("\(DoctorFormatting.timestamp(report.windowStart)) →\n\(DoctorFormatting.timestamp(report.windowEnd))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    coverageBadge(aggregateCoverage)
                }
                Divider()
                HStack(spacing: 16) {
                    levelCount("Errors", count: report.errorCount, color: .red)
                    levelCount("Fault-level", count: report.faultCount, color: .purple)
                    levelCount("Warnings", count: report.warningCount, color: DoctorStyle.warning)
                }
                Divider()
                if let latest = report.latestError {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "exclamationmark.octagon.fill").foregroundColor(.red)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Most recent error record").font(.system(size: 12, weight: .semibold))
                            Text(DoctorFormatting.timestamp(latest.timestamp))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            Text(latest.title).font(.system(size: 12)).foregroundColor(.secondary)
                        }
                        .textSelection(.enabled)
                    }
                } else {
                    Label("No error records in the collected evidence. Fault records are counted separately.", systemImage: "questionmark.circle")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var coverage: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Collection coverage", subtitle: "Availability and limits are part of the result.")
            DoctorCard {
                VStack(alignment: .leading, spacing: 16) {
                    if report.sources.isEmpty {
                        Text("Unknown — no source-coverage information was returned.")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    ForEach(Array(report.sources.enumerated()), id: \.element.id) { index, source in
                        if index > 0 { Divider() }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 14) {
                                Text(source.name).font(.system(size: 13, weight: .semibold))
                                Spacer()
                                coverageBadge(source.state)
                            }
                            Text(source.detail)
                                .font(.system(size: 12)).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            DisclosureGroup {
                                EvidenceList(evidence: source.evidence).padding(.top, 10)
                            } label: {
                                Text("Collection evidence").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                            }
                            .accessibilityIdentifier("log-source-\(source.id)")
                        }
                    }
                    if report.omittedEventCount > 0 {
                        Divider()
                        Label("\(report.omittedEventCount) additional events were omitted by collection limits.", systemImage: "ellipsis.circle")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    Text("Retention, permissions, redaction, and collection limits can leave gaps. Collection never requests administrator access.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Event timeline", subtitle: "Newest first · timestamps include the local time zone")
            HStack(spacing: 16) {
                Picker("Event filter", selection: $filter) {
                    ForEach(EventFilter.allCases) { option in Text(option.rawValue).tag(option) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 360)
                .accessibilityLabel("Filter by log level")
                .accessibilityIdentifier("sleep-wake-filter")
                Spacer(minLength: 0)
                Text("\(visibleEvents.count) shown")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize()
            }
            if visibleEvents.isEmpty {
                DoctorCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(filter == .all ? "No matching events were collected" : "No events match this filter")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Check the source coverage above. An empty timeline does not confirm that sleep or wake worked correctly.")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 12)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleEvents) { event in
                        SleepWakeEventRow(event: event)
                    }
                }
            }
        }
    }

    private func levelCount(_ label: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(count)").font(.system(size: 22, weight: .semibold)).foregroundColor(color)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func coverageBadge(_ state: LogCoverageState) -> some View {
        let icon: String
        let color: Color
        switch state {
        case .available: icon = "checkmark.circle"; color = DoctorStyle.blue
        case .partial: icon = "circle.lefthalf.filled"; color = DoctorStyle.warning
        case .unavailable: icon = "questionmark.circle"; color = .secondary
        }
        return Label(state.rawValue, systemImage: icon)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.08)).clipShape(Capsule())
            .fixedSize()
    }
}

struct SleepWakeEventRow: View {
    let event: SleepWakeEvent

    private var metadata: String {
        var parts = [event.kind.rawValue]
        if let bluetoothEvent = event.bluetoothEvent { parts.append(bluetoothEvent.rawValue) }
        parts.append(event.source)
        return parts.joined(separator: " · ")
    }

    private var color: Color {
        switch event.severity {
        case .information: return DoctorStyle.blue
        case .warning: return DoctorStyle.warning
        case .fault: return .purple
        case .error: return .red
        }
    }

    private var icon: String {
        switch event.kind {
        case .sleep: return "moon.zzz.fill"
        case .wake: return "sunrise.fill"
        case .darkWake: return "moon.circle.fill"
        case .failure: return "exclamationmark.octagon.fill"
        case .relatedError: return "exclamationmark.triangle.fill"
        case .relatedRecord: return "text.bubble.fill"
        }
    }

    var body: some View {
        DoctorCard {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.08)).clipShape(Circle())
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(DoctorFormatting.timestamp(event.timestamp, fractionalSeconds: event.bluetoothEvent != nil))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(event.title).font(.system(size: 14, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .textSelection(.enabled)
                        Spacer(minLength: 0)
                        Text(event.severity.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(color)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(color.opacity(0.08)).clipShape(Capsule())
                            .fixedSize()
                    }
                    Text(metadata)
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(event.detail)
                                .font(.system(size: 12)).foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if let correlation = event.correlation {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Nearby event context").font(.system(size: 11, weight: .semibold))
                                    Text(correlation).font(.system(size: 12)).foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .textSelection(.enabled)
                            }
                            EvidenceList(evidence: event.evidence)
                        }
                        .padding(.top, 10)
                    } label: {
                        Text("Event details & evidence")
                            .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                    }
                    .accessibilityIdentifier("event-evidence-\(event.id)")
                }
            }
        }
    }
}
