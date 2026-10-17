import Foundation

/// A System Profiler snapshot, not a memory stress test or live ECC monitor.
public struct MemoryInfo: Codable, Equatable, Sendable {
    public let section: DiagnosticSection
    public let slots: [MemorySlotInfo]

    public init(section: DiagnosticSection, slots: [MemorySlotInfo]) {
        self.section = section
        self.slots = slots
    }
}

public struct MemorySlotInfo: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let section: DiagnosticSection

    public init(id: String, section: DiagnosticSection) {
        self.id = id
        self.section = section
    }
}
