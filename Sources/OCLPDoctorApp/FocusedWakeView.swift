import DoctorCore
import SwiftUI

struct ErrorCategoryOverview: View {
    let groups: [SleepWakeErrorGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Error records by category", subtitle: "Retained seven-day history. Counts describe log records, not separate incidents.")
            if groups.isEmpty {
                InfoNotice(title: "No matching error records in the retained history", message: "Available logs and collection limits determine what can be counted. An empty category list does not establish successful sleep, wake, or recovery.", icon: "questionmark.circle")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 12) {
                    ForEach(groups) { group in
                        DoctorCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 12) {
                                    Text(group.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Text("\(group.count)")
                                        .font(.system(size: 22, weight: .semibold)).foregroundColor(DoctorStyle.warning)
                                        .fixedSize()
                                }
                                Text("Latest: \(DoctorFormatting.timestamp(group.latestAt))")
                                    .font(.system(size: 10)).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                DisclosureGroup {
                                    Text(group.interpretation)
                                        .font(.system(size: 12)).foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                        .padding(.top, 8)
                                } label: {
                                    Text("What this count means")
                                        .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("sleep-wake-error-categories")
    }
}

struct FocusedWakeView: View {
    let focus: FocusedWakeEvidence

    private var fullScanSummary: FocusedWakeScanSummary? {
        // The core validates the summary's interval and sample count before setting this flag.
        focus.bluetoothSummary.countsAreFromFullScan ? focus.scanSummary : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Latest wake · focused evidence", subtitle: "This focused view overlaps the history above. Do not add the two sets of counts.")
            DoctorCard {
                VStack(alignment: .leading, spacing: 18) {
                    wakeTime
                    Divider()
                    errorCategories
                    Divider()
                    bluetoothEvidence
                    Divider()
                    collectionCoverage
                }
            }
        }
        .accessibilityIdentifier("focused-wake-evidence")
    }

    private var wakeTime: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "sunrise")
                .font(.system(size: 22)).foregroundColor(DoctorStyle.blue)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 7) {
                Text("Wake record").font(.system(size: 12, weight: .semibold))
                Text(DoctorFormatting.timestamp(focus.wakeAt))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Focused window: \(DoctorFormatting.timestamp(focus.start)) → \(DoctorFormatting.timestamp(focus.end))")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if fullScanSummary != nil {
                    Text("\(focus.matchedEventCount) matching collected records · \(focus.displayedEventCount) evidence rows")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(focus.displayedEventCount) retained evidence rows · full scan totals unavailable")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textSelection(.enabled)
        }
    }

    private var errorCategories: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Error categories in this window").font(.system(size: 13, weight: .semibold))
            if let summary = fullScanSummary {
                Text("Counts use all matching collected records before the display limit. Query coverage can still be partial.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Collected levels: \(summary.errorCount) Error · \(summary.faultCount) Fault · \(summary.warningCount) Warning")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Counts use retained evidence rows. They may not represent every matching record returned by the collection.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if focus.errorGroups.isEmpty {
                Text("No matching error records in the available focused counts. This is not a recovery confirmation.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(focus.errorGroups) { group in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(group.title).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Text("\(group.count) records")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary).fixedSize()
                    }
                }
            }
        }
    }

    private var bluetoothEvidence: some View {
        let summary = focus.bluetoothSummary
        return VStack(alignment: .leading, spacing: 12) {
            Text("Bluetooth restart & recovery evidence").font(.system(size: 13, weight: .semibold))
            Text(summary.title)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(summary.detail)
                .font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let start = summary.recurrenceStart, let end = summary.recurrenceEnd {
                Text("Subsequent-record check: \(DoctorFormatting.timestamp(start)) → \(DoctorFormatting.timestamp(end))")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if summary.sequenceOmittedEventCount > 0 {
                Text("Compact sequence: \(summary.sequence.count) samples shown; \(summary.sequenceOmittedEventCount) additional Bluetooth records are not displayed here. The summary was computed before this sequence was shortened.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Chronological order within the focused window. Event order does not establish a cause or prove device or display recovery.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if summary.sequence.isEmpty {
                        Text("No Bluetooth lifecycle samples are available for display.")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    ForEach(summary.sequence) { event in
                        SleepWakeEventRow(event: event)
                    }
                }
                .padding(.top, 12)
            } label: {
                Text("Bluetooth event sequence · \(summary.sequence.count) samples")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
            }
            .accessibilityIdentifier("focused-bluetooth-sequence")
        }
    }

    private var collectionCoverage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Text("Focused collection coverage").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Text(focus.hasIncompleteCoverage ? "Incomplete" : focus.coverage.state.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(focus.hasIncompleteCoverage ? DoctorStyle.warning : DoctorStyle.blue)
                    .fixedSize()
            }
            Text("\(focus.coverage.name) · \(focus.coverage.state.rawValue)")
                .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
            Text(focus.coverage.detail)
                .font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if focus.omittedEventCount > 0 {
                Text(fullScanSummary != nil
                     ? "\(focus.omittedEventCount) matching collected records are not displayed as samples. Their counts remain included above; the display cap does not indicate collection loss."
                     : "\(focus.omittedEventCount) collected records are not displayed as samples. A full scan summary is unavailable, so sample counts alone cannot establish absence or recurrence.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Missing or incomplete records cannot establish that a failure did not recur. A daemon start or controller-ready message does not prove that connected devices recovered.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let segments = focus.segments, !segments.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Each interval has its own collection result. An available later interval does not fill a gap in an earlier interval.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            if index > 0 { Divider() }
                            segmentCoverage(segment)
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    Text("Coverage by interval · \(segments.count) segments")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                }
                .accessibilityIdentifier("focused-coverage-segments")
            }
            DisclosureGroup {
                EvidenceList(evidence: focus.coverage.evidence).padding(.top, 10)
            } label: {
                Text("Collection evidence").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
            }
        }
    }

    private func segmentCoverage(_ segment: FocusedLogSegment) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 14) {
                Text(segment.kind).font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(segment.coverage.state.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(segment.coverage.state == .available ? DoctorStyle.blue : DoctorStyle.warning)
                    .fixedSize()
            }
            Text("\(DoctorFormatting.timestamp(segment.start)) → \(DoctorFormatting.timestamp(segment.end))")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(segment.coverage.detail)
                .font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            DisclosureGroup {
                EvidenceList(evidence: segment.coverage.evidence).padding(.top, 10)
            } label: {
                Text("Segment evidence").font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
    }
}
