import DoctorCore
import SwiftUI

private extension FindingKind {
    var color: Color {
        switch self {
        case .recordedProblem: return DoctorStyle.warning
        case .compatibilityReview: return DoctorStyle.blue
        case .evidenceGap: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .recordedProblem: return "exclamationmark.triangle.fill"
        case .compatibilityReview: return "checklist"
        case .evidenceGap: return "questionmark.circle"
        }
    }
}

struct AttentionFindingsView: View {
    let review: IssueReview
    let onOpenPage: (String) -> Void
    @State private var showCompatibility: Bool
    @State private var showEvidenceGaps = false

    init(review: IssueReview, onOpenPage: @escaping (String) -> Void) {
        self.review = review
        self.onOpenPage = onOpenPage
        _showCompatibility = State(initialValue: !review.findings.contains { $0.kind == .recordedProblem })
    }

    private var recordedProblems: [IssueFinding] { review.findings.filter { $0.kind == .recordedProblem } }
    private var compatibilityReviews: [IssueFinding] { review.findings.filter { $0.kind == .compatibilityReview } }
    private var evidenceGaps: [IssueFinding] { review.findings.filter { $0.kind == .evidenceGap } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                SectionHeading(title: "Needs your attention", subtitle: "Recorded problems, compatibility questions, and evidence gaps come first.")
                Spacer(minLength: 0)
                Button("Known Issues") { onOpenPage("knownIssues") }
                    .accessibilityIdentifier("open-known-issues")
            }
            if review.findings.isEmpty {
                InfoNotice(
                    title: "No problems identified in collected evidence",
                    message: "This is not a complete health check. Unknown observations, unavailable logs, and issues outside the bundled catalog may still need investigation.",
                    icon: "info.circle"
                )
            } else {
                Text("A compatibility review is a possible risk to check, not a confirmed failure. A recorded problem does not establish its cause or current impact.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !recordedProblems.isEmpty {
                    groupLabel("Recorded problems", count: recordedProblems.count, icon: "exclamationmark.triangle.fill", color: DoctorStyle.warning)
                    ForEach(recordedProblems) { finding in
                        findingCard(finding)
                    }
                }
                if !compatibilityReviews.isEmpty {
                    Divider()
                    DisclosureGroup(isExpanded: $showCompatibility) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(compatibilityReviews) { finding in findingCard(finding) }
                        }
                        .padding(.top, 12)
                    } label: {
                        groupLabel("Compatibility reviews", count: compatibilityReviews.count, icon: "checklist", color: DoctorStyle.blue)
                    }
                    .accessibilityIdentifier("overview-compatibility-reviews")
                }
                if !evidenceGaps.isEmpty {
                    Divider()
                    DisclosureGroup(isExpanded: $showEvidenceGaps) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(evidenceGaps) { finding in findingCard(finding) }
                        }
                        .padding(.top, 12)
                    } label: {
                        groupLabel("Evidence gaps", count: evidenceGaps.count, icon: "questionmark.circle", color: .secondary)
                    }
                    .accessibilityIdentifier("overview-evidence-gaps")
                }
            }
        }
        .accessibilityIdentifier("overview-attention-findings")
    }

    private func groupLabel(_ title: String, count: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(color)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.primary.opacity(0.05)).clipShape(Capsule())
        }
        .padding(.vertical, 3)
    }

    private func findingCard(_ finding: IssueFinding) -> some View {
        DoctorCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Label(finding.kind.rawValue, systemImage: finding.kind.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(finding.kind.color)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(finding.kind.color.opacity(0.08))
                        .clipShape(Capsule())
                    Spacer(minLength: 0)
                    Text("\(finding.priority.rawValue) priority")
                        .font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                        .fixedSize()
                }
                Text(finding.title)
                    .font(.system(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text(finding.detail)
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 17) {
                        SuggestedChecks(steps: finding.nextSteps)
                        EvidenceList(evidence: finding.evidence)
                        OfficialSourceLinks(sources: finding.sources)
                    }
                    .padding(.top, 12)
                } label: {
                    Text("Suggested checks & evidence")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                }
                .accessibilityIdentifier("finding-evidence-\(finding.id)")
                Button {
                    onOpenPage(finding.relatedPage)
                } label: {
                    Label(relatedPageLabel(finding.relatedPage), systemImage: "arrow.right.circle")
                }
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .medium))
                .accessibilityIdentifier("finding-details-\(finding.id)")
            }
        }
    }

    private func relatedPageLabel(_ name: String) -> String {
        switch name {
        case "sleepWake": return "Open Sleep & Wake"
        case "hardware": return "Open Hardware"
        case "bootSecurity": return "Open Boot & Security"
        case "patches": return "Open Patches"
        case "knownIssues": return "Review Known Issues"
        default: return "Open related details"
        }
    }
}

struct KnownIssuesView: View {
    let review: IssueReview
    @State private var project = "All projects"
    @State private var search = ""

    private var projects: [String] { Array(Set(review.catalog.map(\.project))).sorted() }
    private var visibleIssues: [KnownIssue] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return review.catalog.filter { issue in
            (project == "All projects" || project == issue.project)
                && (query.isEmpty || "\(issue.title) \(issue.project) \(issue.summary) \(issue.scope)".localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            InfoNotice(
                title: "Curated offline catalog · reviewed \(review.reviewedOn)",
                message: "These official references are bundled with this app and are not exhaustive. Upstream status may have changed since review. Refresh collects local diagnostics; it does not check the web. Open a source link to review the latest information.",
                icon: "books.vertical"
            )
            HStack(spacing: 14) {
                TextField("Filter by issue, project, or scope", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("known-issues-search")
                Picker("Project", selection: $project) {
                    Text("All projects").tag("All projects")
                    ForEach(projects, id: \.self) { value in Text(value).tag(value) }
                }
                .labelsHidden()
                .frame(width: 220)
                .accessibilityLabel("Filter known issues by project")
                .accessibilityIdentifier("known-issues-project-filter")
            }
            Text("\(visibleIssues.count) of \(review.catalog.count) catalog entries")
                .font(.system(size: 11)).foregroundColor(.secondary)
            if visibleIssues.isEmpty {
                DoctorCard {
                    Text("No catalog entries match this filter.")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(visibleIssues) { issue in
                        KnownIssueCard(issue: issue)
                    }
                }
            }
        }
        .accessibilityIdentifier("known-issues-catalog")
    }
}

private struct KnownIssueCard: View {
    let issue: KnownIssue

    var body: some View {
        DoctorCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(issue.project)
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(DoctorStyle.blue)
                    Spacer(minLength: 0)
                    Text("Reviewed \(issue.reviewedOn)")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                        .fixedSize()
                }
                Text(issue.title)
                    .font(.system(size: 17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text(issue.summary)
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                VStack(alignment: .leading, spacing: 9) {
                    metadata("Scope", value: issue.scope)
                    metadata("Upstream status at review", value: issue.upstreamStatus)
                }
                Divider()
                if !issue.nextSteps.isEmpty {
                    DisclosureGroup {
                        SuggestedChecks(steps: issue.nextSteps).padding(.top, 10)
                    } label: {
                        Text("Suggested checks").font(.system(size: 11, weight: .medium))
                    }
                    .accessibilityIdentifier("known-issue-checks-\(issue.id)")
                }
                OfficialSourceLinks(sources: issue.sources)
            }
        }
    }

    private func metadata(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold))
            Text(value)
                .font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

private struct SuggestedChecks: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 9) {
                    Text("\(index + 1).")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(DoctorStyle.blue)
                        .frame(width: 20, alignment: .leading)
                    Text(step)
                        .font(.system(size: 12)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct OfficialSourceLinks: View {
    let sources: [IssueSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !sources.isEmpty {
                Text("Official references")
                    .font(.system(size: 11, weight: .semibold))
                ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                    if let url = URL(string: source.url), url.scheme?.lowercased() == "https" {
                        Link(destination: url) {
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                                Text(source.title)
                                    .font(.system(size: 12))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .help(source.url)
                    } else {
                        Text(source.title).font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
