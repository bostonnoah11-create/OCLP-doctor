import AppKit
import DoctorCore
import SwiftUI

enum DoctorStyle {
    static let accent = Color.accentColor
    static let blue = adaptive(light: (0.04, 0.36, 0.79), dark: (0.38, 0.66, 1.0))
    static let success = adaptive(light: (0.13, 0.43, 0.25), dark: (0.43, 0.82, 0.56))
    static let warning = adaptive(light: (0.60, 0.34, 0.02), dark: (1.0, 0.71, 0.30))
    static let card = Color(nsColor: .controlBackgroundColor)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let border = Color.primary.opacity(0.08)

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }
}

/// Decorative branding only; the generated raster asset is supplied by the app bundle.
struct BrandMark: View {
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let icon = NSImage(named: NSImage.Name("AppIconPreview")) {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(DoctorStyle.blue)
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: size * 0.46, weight: .medium))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Real Liquid Glass is reserved for compact chrome, not hundreds of diagnostic rows.
struct DoctorGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 18
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(DoctorStyle.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Color.primary.opacity(0.22), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

struct DoctorBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            DoctorStyle.background
            if !reduceTransparency && contrast != .increased {
                LinearGradient(colors: [DoctorStyle.blue.opacity(scheme == .dark ? 0.10 : 0.065), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

enum DoctorFormatting {
    static func timestamp(_ date: Date, fractionalSeconds: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = fractionalSeconds ? "MMM d, yyyy 'at' HH:mm:ss.SSS z" : "MMM d, yyyy 'at' HH:mm:ss z"
        return formatter.string(from: date)
    }
}

extension DiagnosticStatus {
    var icon: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .healthy: return DoctorStyle.success
        case .attention: return DoctorStyle.warning
        case .unknown: return .secondary
        }
    }

    var explanation: String {
        switch self {
        case .healthy: return "Observation confirmed"
        case .attention: return "Needs a closer look"
        case .unknown: return "More evidence needed"
        }
    }
}

struct StatusBadge: View {
    let status: DiagnosticStatus

    var body: some View {
        Label(status.rawValue, systemImage: status.icon)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.09))
            .clipShape(Capsule())
            .fixedSize()
            .accessibilityLabel("\(status.rawValue): \(status.explanation)")
    }
}

struct DoctorCard<Content: View>: View {
    private let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        let opaque = reduceTransparency || contrast == .increased
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(DoctorStyle.card.opacity(opaque ? 1 : (scheme == .dark ? 0.94 : 0.88)))
                    .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(opaque ? 0 : (scheme == .dark ? 0.025 : 0.20)), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.24 : 0.07), lineWidth: 1))
            .shadow(color: .black.opacity(opaque ? 0 : (scheme == .dark ? 0.10 : 0.025)), radius: 10, x: 0, y: 4)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 16, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct InfoNotice: View {
    let title: String
    let message: String
    var icon = "info.circle"
    var color = DoctorStyle.blue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DoctorStyle.card.opacity(reduceTransparency || contrast == .increased ? 1 : 0.55))
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(contrast == .increased ? 0.40 : 0.13), lineWidth: 1))
    }
}

struct EvidenceList: View {
    let evidence: [Evidence]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if evidence.isEmpty {
                Text("No supporting evidence is available.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(evidence.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.source)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Text(entry.detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.system(size: 11))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct EvidenceDisclosure: View {
    let item: DiagnosticItem

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                EvidenceList(evidence: item.evidence)
            }
            .padding(.top, 10)
            .padding(.leading, 4)
            .fixedSize(horizontal: false, vertical: true)
        } label: {
            Text("Details & evidence")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .accessibilityLabel("Details and evidence for \(item.label)")
        .accessibilityIdentifier("evidence-\(item.id)")
    }
}

struct DiagnosticItemRow: View {
    let item: DiagnosticItem

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 16) {
                Text(item.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 165, alignment: .leading)
                Text(item.displayValue)
                    .font(.system(size: 13, weight: .medium))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatusBadge(status: item.status)
            }
            if item.status != .healthy {
                Text(item.message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            EvidenceDisclosure(item: item)
        }
        .padding(.vertical, 7)
    }
}

struct DiagnosticSectionCard: View {
    let section: DiagnosticSection
    var icon = "list.bullet.rectangle"

    var body: some View {
        DoctorCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 9) {
                    Image(systemName: icon).foregroundColor(DoctorStyle.blue)
                    Text(section.title)
                    Spacer()
                    Text("\(section.items.count) items")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 14, weight: .semibold))
                Divider()
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    DiagnosticItemRow(item: item)
                }
                if section.items.isEmpty {
                    Text("Unknown — no information was collected.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct OverviewTile: View {
    let item: DiagnosticItem
    let icon: String

    var body: some View {
        DoctorCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DoctorStyle.blue)
                    Text(item.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }
                Text(item.displayValue)
                    .font(.system(size: 17, weight: .semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                StatusBadge(status: item.status)
                EvidenceDisclosure(item: item)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
