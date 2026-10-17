import DoctorCore
import SwiftUI

struct MemoryDetailsView: View {
    let memory: MemoryInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Memory & ECC", subtitle: "Reported configuration and counters. This is not a memory stress test or a live ECC monitor.")
            DiagnosticSectionCard(section: memory.section, icon: "memorychip")
            if memory.slots.isEmpty {
                InfoNotice(title: "Slot details unavailable", message: "No individual memory slots were reported. Unknown slot data does not identify a failed module.", icon: "questionmark.circle")
            } else {
                DoctorCard {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Reported memory slots").font(.system(size: 14, weight: .semibold))
                        ForEach(Array(memory.slots.enumerated()), id: \.element.id) { index, slot in
                            if index > 0 { Divider() }
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(slot.section.items.enumerated()), id: \.element.id) { itemIndex, item in
                                        if itemIndex > 0 { Divider() }
                                        DiagnosticItemRow(item: item)
                                    }
                                }
                                .padding(.top, 12)
                            } label: {
                                slotSummary(slot)
                            }
                            .accessibilityIdentifier("memory-slot-\(slot.id)")
                        }
                        Text("A reported OK status or ECC capability does not prove that RAM is fault-free. Missing ECC counters remain Unknown.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityIdentifier("hardware-memory-ecc")
    }

    private func slotSummary(_ slot: MemorySlotInfo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(slot.section.title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Text(value(slot, "size")).font(.system(size: 13, weight: .semibold))
                    .fixedSize()
            }
            Text("\(value(slot, "type")) · \(value(slot, "speed")) · Reported status: \(value(slot, "status"))")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Correctable ECC count: \(value(slot, "correctableECCErrors"))")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }

    private func value(_ slot: MemorySlotInfo, _ suffix: String) -> String {
        slot.section.item("\(slot.id)-\(suffix)")?.displayValue ?? "Unknown"
    }
}
