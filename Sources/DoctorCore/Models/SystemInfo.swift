import Foundation

public enum DiagnosticStatus: String, Codable, CaseIterable, Sendable {
    case healthy = "Healthy"
    case attention = "Attention"
    case unknown = "Unknown"
}

public struct Evidence: Codable, Equatable, Sendable {
    public let source: String
    public let detail: String
    public init(source: String, detail: String) {
        self.source = source
        self.detail = detail
    }
}

/// A confirmed observation is not a claim that the whole component is healthy.
public struct DiagnosticItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let value: String?
    public let status: DiagnosticStatus
    public let message: String
    public let evidence: [Evidence]

    public init(id: String, label: String, value: String?, status: DiagnosticStatus = .healthy,
                message: String = "This value was observed. It does not prove that the entire component is working correctly.",
                evidence: [Evidence] = []) {
        self.id = id
        self.label = label
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = trimmed?.isEmpty == false ? trimmed : nil
        self.status = self.value == nil ? .unknown : status
        self.message = message
        self.evidence = evidence
    }

    public var displayValue: String { value ?? "Unknown" }
}

public struct DiagnosticSection: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let items: [DiagnosticItem]
    public init(id: String, title: String, items: [DiagnosticItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
    public func item(_ id: String) -> DiagnosticItem? { items.first { $0.id == id } }
}

public struct GPUInfo: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: DiagnosticItem
    public let vram: DiagnosticItem
    public let metal: DiagnosticItem
    public init(id: String, name: DiagnosticItem, vram: DiagnosticItem, metal: DiagnosticItem) {
        self.id = id
        self.name = name
        self.vram = vram
        self.metal = metal
    }
    public var section: DiagnosticSection {
        DiagnosticSection(id: id, title: "GPU · \(name.displayValue)", items: [name, vram, metal])
    }
}

public struct HardwareInfo: Codable, Equatable, Sendable {
    public let section: DiagnosticSection
    public let gpus: [GPUInfo]
    public let memory: MemoryInfo?
    public init(section: DiagnosticSection, gpus: [GPUInfo], memory: MemoryInfo? = nil) {
        self.section = section
        self.gpus = gpus
        self.memory = memory
    }
}

public struct SystemInfo: Codable, Sendable {
    public let capturedAt: Date
    public let duration: TimeInterval
    public let hardware: HardwareInfo
    public let os: DiagnosticSection
    public let boot: DiagnosticSection
    public let security: DiagnosticSection
    public let patches: DiagnosticSection
    public let isDemo: Bool
    public let sleepWake: SleepWakeReport?

    public init(capturedAt: Date, duration: TimeInterval, hardware: HardwareInfo,
                os: DiagnosticSection, boot: DiagnosticSection, security: DiagnosticSection,
                patches: DiagnosticSection, isDemo: Bool = false, sleepWake: SleepWakeReport? = nil) {
        self.capturedAt = capturedAt
        self.duration = duration
        self.hardware = hardware
        self.os = os
        self.boot = boot
        self.security = security
        self.patches = patches
        self.isDemo = isDemo
        self.sleepWake = sleepWake
    }
    public var sections: [DiagnosticSection] {
        [hardware.section] + hardware.gpus.map(\.section)
            + (hardware.memory.map { [$0.section] + $0.slots.map(\.section) } ?? [])
            + [os, boot, security, patches] + (sleepWake.map { [$0.section] } ?? [])
    }
    public var items: [DiagnosticItem] { sections.flatMap(\.items) }

    private enum CodingKeys: String, CodingKey {
        case capturedAt, duration, hardware, os, boot, security, patches, isDemo, sleepWake
    }
    private enum ReviewCodingKey: String, CodingKey { case issueReview }

    /// Export the dated evaluation alongside original observations. Decoding recomputes it locally,
    /// rather than trusting a previously serialized finding or a stale catalog as a new diagnosis.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(duration, forKey: .duration)
        try container.encode(hardware, forKey: .hardware)
        try container.encode(os, forKey: .os)
        try container.encode(boot, forKey: .boot)
        try container.encode(security, forKey: .security)
        try container.encode(patches, forKey: .patches)
        try container.encode(isDemo, forKey: .isDemo)
        try container.encodeIfPresent(sleepWake, forKey: .sleepWake)
        var review = encoder.container(keyedBy: ReviewCodingKey.self)
        try review.encode(issueReview, forKey: .issueReview)
    }
}
