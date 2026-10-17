import DoctorCore
import SwiftUI

private enum DoctorPage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case hardware = "Hardware"
    case bootSecurity = "Boot & Security"
    case patches = "Patches"
    case sleepWake = "Sleep & Wake"
    case knownIssues = "Known Issues"
    case report = "Report"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .hardware: return "desktopcomputer"
        case .bootSecurity: return "lock.shield"
        case .patches: return "puzzlepiece.extension"
        case .sleepWake: return "moon.zzz"
        case .knownIssues: return "book.closed"
        case .report: return "doc.text"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "Your Mac, its configuration, and the evidence behind each finding."
        case .hardware: return "Hardware and graphics devices reported by macOS."
        case .bootSecurity: return "OpenCore boot evidence and the current security configuration."
        case .patches: return "Installed OCLP software and available root-patch records."
        case .sleepWake: return "A read-only timeline of sleep, wake, and related log records."
        case .knownIssues: return "A dated review of official OpenCore and OCLP issue references."
        case .report: return "A complete local report, with timestamps and supporting evidence."
        }
    }
}

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @State private var selection: DoctorPage?

    init(model: DashboardModel) {
        self.model = model
        // Explicit development/verification launch option; ordinary launches use Overview.
        let showTimeline = ProcessInfo.processInfo.arguments.contains("--show-sleep-wake")
        let showKnownIssues = ProcessInfo.processInfo.arguments.contains("--show-known-issues")
        let showHardware = ProcessInfo.processInfo.arguments.contains("--show-hardware")
        let initialPage: DoctorPage
        if showKnownIssues {
            initialPage = .knownIssues
        } else if showHardware {
            initialPage = .hardware
        } else {
            initialPage = showTimeline ? .sleepWake : .overview
        }
        _selection = State(initialValue: initialPage)
    }

    private var page: DoctorPage { selection ?? .overview }

    var body: some View {
        NavigationView {
            sidebar
                .frame(minWidth: 215, idealWidth: 230, maxWidth: 255)
                .background(WindowLayoutProbe(id: "sidebar"))
            VStack(spacing: 0) {
                pageHeader
                    .background(WindowLayoutProbe(id: "header"))
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if model.isDemo {
                            InfoNotice(
                                title: "Demo mode · synthetic data",
                                message: "These examples test the interface and collection failures. They are not measurements from this Mac.",
                                icon: "flask",
                                color: DoctorStyle.warning
                            )
                        }
                        if let snapshot = model.snapshot {
                            pageContent(snapshot)
                            captureFooter(snapshot)
                        } else {
                            loadingState
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(minWidth: 0, maxWidth: 1180, alignment: .leading)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .background(DoctorBackdrop())
                .background(WindowLayoutProbe(id: "viewport"))
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        }
        .accentColor(DoctorStyle.blue)
        .navigationTitle("OCLP Doctor")
        .toolbar {
            ToolbarItem {
                HStack(spacing: 10) {
                    if model.isCollecting { ProgressView().controlSize(.small) }
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isCollecting)
                    .controlSize(.regular)
                    .help("Run read-only diagnostics again. ⌘R")
                    .accessibilityIdentifier("refresh-diagnostics")
                }
            }
        }
        .task {
            await model.startIfNeeded()
            await WindowLayoutVerification.run(pages: DoctorPage.allCases.map(\.rawValue)) { name in
                if let next = DoctorPage(rawValue: name) { selection = next }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text("OCLP Doctor").font(.system(size: 16, weight: .semibold))
                    Text("Beta 0.5.1").font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 19)
            .padding(.top, 20)
            .padding(.bottom, 24)

            Text("DIAGNOSTICS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(.secondary)
                .padding(.horizontal, 21)
                .padding(.bottom, 7)

            List(selection: $selection) {
                ForEach(DoctorPage.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.vertical, 7)
                        .tag(item)
                        .accessibilityIdentifier("navigation-\(item.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")
                }
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 11) {
                Label("Read-only diagnostics", systemImage: "lock.shield")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DoctorStyle.blue)
                Text("Collected locally. Nothing is uploaded.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Divider()
                Text("An independent, unofficial project. Not affiliated with Dortania or the OCLP developers.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text(page.rawValue).font(.system(size: 28, weight: .semibold))
                Text(page.subtitle).font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 7) {
                Label("Read-only", systemImage: "lock.shield")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DoctorStyle.blue)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .modifier(DoctorGlassSurface(cornerRadius: 24))
                    .fixedSize()
                if model.isCollecting {
                    Text(model.snapshot == nil ? "Collecting…" : "Refreshing…\nShowing previous results")
                        .font(.system(size: 10))
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(DoctorBackdrop())
    }

    @ViewBuilder
    private func pageContent(_ snapshot: SystemInfo) -> some View {
        switch page {
        case .overview:
            overview(snapshot)
        case .hardware:
            DiagnosticSectionCard(section: snapshot.hardware.section, icon: "desktopcomputer")
            if let memory = snapshot.hardware.memory {
                MemoryDetailsView(memory: memory)
            } else {
                InfoNotice(title: "Memory-slot and ECC information unavailable", message: "No memory-slot report was collected. Capacity alone does not establish RAM health or ECC support.", icon: "memorychip")
            }
            SectionHeading(title: "Graphics devices", subtitle: "Each device is shown separately. Reported Metal support is not a live acceleration test.")
            if snapshot.hardware.gpus.isEmpty {
                InfoNotice(title: "Graphics information unavailable", message: "No verifiable graphics-device information was returned. This does not mean the Mac has no GPU.", icon: "questionmark.circle")
            }
            ForEach(snapshot.hardware.gpus) { gpu in
                DiagnosticSectionCard(section: gpu.section, icon: "display")
            }
            DiagnosticSectionCard(section: snapshot.os, icon: "applelogo")
        case .bootSecurity:
            InfoNotice(
                title: "Interpret security settings in context",
                message: "A reduced SIP configuration can be required by OCLP patches. Installed OCLP software and evidence of the active OpenCore boot environment are reported separately.",
                icon: "lock.shield"
            )
            DiagnosticSectionCard(section: snapshot.boot, icon: "power")
            DiagnosticSectionCard(section: snapshot.security, icon: "lock.shield")
        case .patches:
            InfoNotice(
                title: "Patch records do not prove runtime behavior",
                message: "An installed app or patch record does not establish that every patch or graphics driver is working. Findings remain Unknown when evidence is insufficient.",
                icon: "puzzlepiece.extension"
            )
            DiagnosticSectionCard(section: snapshot.patches, icon: "puzzlepiece.extension")
        case .report:
            reportView(snapshot)
        case .sleepWake:
            if let sleepWake = snapshot.sleepWake {
                SleepWakeView(report: sleepWake)
            } else {
                InfoNotice(title: "Sleep & wake information unavailable", message: "This diagnostic does not contain a log timeline. Refresh to request a new collection. No conclusion about sleep or wake can be drawn.", icon: "questionmark.circle")
            }
        case .knownIssues:
            KnownIssuesView(review: snapshot.issueReview)
        }
    }

    private func overview(_ snapshot: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            DoctorCard {
                HStack(alignment: .center, spacing: 18) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(DoctorStyle.blue)
                        .frame(width: 62, height: 62)
                        .modifier(DoctorGlassSurface(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.hardware.overviewModelTitle)
                            .font(.system(size: 22, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) {
                            Text(snapshot.hardware.section.item("modelIdentifier")?.displayValue ?? "Unknown model")
                                .font(.system(size: 12, design: .monospaced))
                            Text("macOS \(snapshot.os.item("productVersion")?.displayValue ?? "Unknown")")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.secondary)
                        Text(snapshot.hardware.overviewModelNote)
                            .font(.system(size: 10)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }

            AttentionFindingsView(review: snapshot.issueReview, onOpenPage: openRelatedPage)

            SectionHeading(title: "Collected observations", subtitle: "Individual item states, after the findings that need review.")
            HStack(spacing: 14) {
                ForEach([DiagnosticStatus.attention, .unknown, .healthy], id: \.self) { status in
                    DoctorCard {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: status.icon)
                                .font(.system(size: 18)).foregroundColor(status.color)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(snapshot.items.filter { $0.status == status }.count)  \(status.rawValue)")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(status.explanation).font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            Text("Healthy describes an individual observation, not overall system reliability. Unknown means the available evidence is insufficient.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .padding(.top, -10)

            if let sleepWake = snapshot.sleepWake {
                Button { selection = .sleepWake } label: {
                    DoctorCard {
                        HStack(spacing: 14) {
                            Image(systemName: "moon.zzz")
                                .font(.system(size: 22)).foregroundColor(DoctorStyle.blue)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Sleep & wake timeline").font(.system(size: 14, weight: .semibold))
                                Text("\(sleepWake.events.count) events · \(sleepWake.errorCount) error records · \(sleepWake.faultCount) Fault-level · last 7 days")
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let error = sleepWake.latestError {
                                    Text("Latest error record: \(DoctorFormatting.timestamp(error.timestamp))")
                                        .font(.system(size: 11)).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open-sleep-wake-timeline")
            }

            SectionHeading(title: "Hardware at a glance", subtitle: "Open an item's details to inspect its source and interpretation.")
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], alignment: .leading, spacing: 16) {
                if let cpu = snapshot.hardware.section.item("cpu") { OverviewTile(item: cpu, icon: "cpu") }
                if let ram = snapshot.hardware.section.item("memory") { OverviewTile(item: ram, icon: "memorychip") }
                ForEach(snapshot.hardware.gpus) { gpu in OverviewTile(item: gpu.name, icon: "display") }
                if snapshot.hardware.gpus.isEmpty, let graphics = snapshot.hardware.section.item("gpuCount") {
                    OverviewTile(item: graphics, icon: "display")
                }
            }

            SectionHeading(title: "OpenCore & patches", subtitle: "Boot evidence and installed software are distinct observations.")
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], alignment: .leading, spacing: 16) {
                if let openCore = snapshot.boot.item("openCoreVersion") { OverviewTile(item: openCore, icon: "power") }
                if let oclp = snapshot.patches.item("installedOCLP") { OverviewTile(item: oclp, icon: "shippingbox") }
                if let patch = snapshot.patches.item("rootPatchState") { OverviewTile(item: patch, icon: "puzzlepiece.extension") }
            }
        }
    }

    private func openRelatedPage(_ name: String) {
        switch name {
        case "sleepWake": selection = .sleepWake
        case "hardware": selection = .hardware
        case "bootSecurity": selection = .bootSecurity
        case "patches": selection = .patches
        case "knownIssues": selection = .knownIssues
        default: break
        }
    }

    private func reportView(_ snapshot: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            DoctorCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Diagnostic report").font(.system(size: 15, weight: .semibold))
                            Text("\(DoctorFormatting.timestamp(snapshot.capturedAt)) · \(String(format: "%.1f", snapshot.duration)) seconds")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button { model.copyReport() } label: {
                            Label("Copy Report", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Copy the complete report to the clipboard. ⇧⌘C")
                        .accessibilityIdentifier("copy-report")
                    }
                    Text("Review the contents before sharing. Copy Report writes the report to the system clipboard only when you select it.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    if let copyMessage = model.copyMessage {
                        Text(copyMessage)
                            .font(.system(size: 12, weight: .medium)).foregroundColor(DoctorStyle.blue)
                    }
                }
            }
            DoctorCard {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(model.reportParagraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.system(size: 11, design: .monospaced))
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("diagnostic-report")
            }
        }
    }

    private var loadingState: some View {
        DoctorCard {
            VStack(alignment: .center, spacing: 18) {
                ProgressView().controlSize(.large)
                Text("Getting to know your Mac")
                    .font(.system(size: 19, weight: .semibold))
                Text("Reading hardware, boot, security, and sleep/wake logs.\nThe latest wake is queried before broader history; dense log bursts can take one to two minutes.\nUnavailable information will be marked Unknown.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Label("Your system settings stay unchanged", systemImage: "lock.shield")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(DoctorStyle.blue)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)
        }
    }

    private func captureFooter(_ snapshot: SystemInfo) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "clock")
            Text("Collected \(DoctorFormatting.timestamp(snapshot.capturedAt))")
            Text("· \(String(format: "%.1f", snapshot.duration)) seconds")
            Spacer()
        }
        .font(.system(size: 10)).foregroundColor(.secondary)
        .textSelection(.enabled)
        .padding(.horizontal, 2)
    }
}
