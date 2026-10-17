import Foundation
import Testing
@testable import DoctorCore

@Suite
struct MemoryTests {
    @Test
    func fourECCSlotsPreserveObservedValuesAndHealthLimits() async throws {
        let slots = (1...4).map { index -> [String: Any] in
            ["_name": "DIMM\(index)", "dimm_size": "16 GB", "dimm_type": "DDR3 ECC",
             "dimm_speed": "1600 MHz", "dimm_status": "ok",
             "dimm_manufacturer": "PRIVATE-MANUFACTURER", "dimm_part_number": "PRIVATE-PART",
             "dimm_serial_number": "PRIVATE-SERIAL"]
        }
        let memory = try await collect(group: ["global_ecc_state": "ecc_enabled", "_items": slots])
        #expect(memory.section.id == "memory")
        #expect(memory.section.item("memory-ecc")?.value == "Enabled")
        #expect(memory.section.item("memory-slotCount")?.value == "4")
        #expect(memory.section.item("memory-eccAssessment")?.status == .unknown)
        #expect(memory.section.item("memory-eccAssessment")?.message.contains("no memory test is run") == true)
        #expect(memory.slots.map(\.id) == ["memory-slot-0", "memory-slot-1", "memory-slot-2", "memory-slot-3"])
        for (index, slot) in memory.slots.enumerated() {
            let id = slot.id
            #expect(slot.section.item("\(id)-location")?.value == "DIMM\(index + 1)")
            #expect(slot.section.item("\(id)-size")?.value == "16 GB")
            #expect(slot.section.item("\(id)-type")?.value == "DDR3 ECC")
            #expect(slot.section.item("\(id)-speed")?.value == "1600 MHz")
            #expect(slot.section.item("\(id)-status")?.value == "OK")
            #expect(slot.section.item("\(id)-correctableECCErrors")?.value == nil)
            #expect(slot.section.item("\(id)-correctableECCErrors")?.status == .unknown)
            #expect(slot.section.items.allSatisfy { !$0.evidence.isEmpty })
        }
        let encoded = String(decoding: try JSONEncoder().encode(memory), as: UTF8.self)
        #expect(!encoded.contains("PRIVATE-"))
        #expect(!encoded.contains("dimm_serial_number"))
        #expect(!encoded.contains("dimm_part_number"))
    }

    @Test
    func eccTypeDoesNotInferModeAndDisabledModeIsNotAnError() async throws {
        let missing = try await collect(group: ["_items": [["_name": "DIMM1", "dimm_type": "DDR3 ECC"]]])
        #expect(missing.section.item("memory-ecc")?.value == nil)
        #expect(missing.section.item("memory-ecc")?.status == .unknown)
        #expect(missing.slots[0].section.item("memory-slot-0-type")?.value == "DDR3 ECC")
        let disabled = try await collect(group: ["global_ecc_state": "ecc_disabled", "_items": []])
        #expect(disabled.section.item("memory-ecc")?.value == "Disabled")
        #expect(disabled.section.item("memory-ecc")?.status == .healthy)
        #expect(disabled.section.item("memory-eccAssessment")?.status == .unknown)
    }

    @Test
    func reportedSlotProblemsAndPositiveCorrectableCountsNeedAttention() async throws {
        let memory = try await collect(group: ["_items": [
            ["_name": "DIMM1", "dimm_status": "mapped_out"],
            ["_name": "DIMM2", "dimm_status": "ecc_errors", "dimm_ecc_errors": 3],
            ["_name": "DIMM3", "dimm_status": "ok", "dimm_ecc_errors": "0002"]
        ]])
        #expect(memory.slots[0].section.item("memory-slot-0-status")?.value == "Mapped Out")
        #expect(memory.slots[0].section.item("memory-slot-0-status")?.status == .attention)
        #expect(memory.slots[1].section.item("memory-slot-1-status")?.value == "ECC Errors Reported")
        #expect(memory.slots[1].section.item("memory-slot-1-correctableECCErrors")?.value == "3")
        #expect(memory.slots[2].section.item("memory-slot-2-correctableECCErrors")?.value == "2")
        #expect(memory.slots[2].section.item("memory-slot-2-correctableECCErrors")?.status == .attention)
        #expect(memory.slots[2].section.item("memory-slot-2-correctableECCErrors")?.message.contains("reset period") == true)
    }

    @Test
    func zeroCorrectableErrorsDoNotProveErrorFreeMemory() async throws {
        let memory = try await collect(group: ["_items": [["_name": "DIMM1", "dimm_status": "ok", "dimm_ecc_errors": 0]]])
        #expect(memory.slots[0].section.item("memory-slot-0-correctableECCErrors")?.value == "0")
        #expect(memory.section.item("memory-eccAssessment")?.status == .unknown)
        #expect(memory.section.item("memory-eccAssessment")?.message.contains("do not prove error-free RAM") == true)
    }

    @Test
    func emptySlotsAndNotebookBankLabelsRemainReportedObservations() async throws {
        let memory = try await collect(group: ["_items": [
            ["_name": "BANK 0/DIMM0", "dimm_size": "8 GB", "dimm_type": "DDR3", "dimm_speed": "1600 MHz", "dimm_status": "ok"],
            ["_name": "BANK 1/DIMM0", "dimm_size": "empty", "dimm_status": "empty"]
        ]])
        #expect(memory.section.item("memory-slotCount")?.value == "2")
        #expect(memory.slots[0].section.item("memory-slot-0-location")?.value == "BANK 0/DIMM0")
        #expect(memory.slots[1].section.item("memory-slot-1-size")?.value == "Empty")
        #expect(memory.slots[1].section.item("memory-slot-1-status")?.value == "Empty")
        #expect(memory.slots[1].section.item("memory-slot-1-status")?.status == .healthy)
        #expect(memory.slots[1].section.item("memory-slot-1-correctableECCErrors")?.status == .unknown)
    }

    @Test
    func invalidCountsRemainUnknownRatherThanZeroOrErrors() async throws {
        let invalid: [Any] = [true, false, -1, 1.5, "-1", "0 errors", "18446744073709551616", "PRIVATE-COUNT", NSNull()]
        for value in invalid {
            let memory = try await collect(group: ["_items": [["_name": "DIMM1", "dimm_ecc_errors": value]]])
            let item = memory.slots[0].section.item("memory-slot-0-correctableECCErrors")
            #expect(item?.value == nil)
            #expect(item?.status == .unknown)
        }
    }

    @Test
    func malformedFieldsAndPrivateValuesAreWithheld() async throws {
        let memory = try await collect(group: ["global_ecc_state": "PRIVATE-ECC", "_items": [[
            "_name": "/Users/PRIVATE-NAME/DIMM1", "dimm_size": "PRIVATE-SIZE", "dimm_speed": "PRIVATE-SPEED",
            "dimm_type": "PRIVATE-TYPE", "dimm_status": "PRIVATE-STATUS", "dimm_ecc_errors": "PRIVATE-COUNT",
            "dimm_part_number": "PRIVATE-PART", "dimm_serial_number": "PRIVATE-SERIAL"
        ]]])
        #expect(memory.section.item("memory-ecc")?.status == .unknown)
        #expect(memory.slots[0].section.items.allSatisfy { $0.value == nil && $0.status == .unknown })
        #expect(memory.slots[0].section.title == "RAM · Slot record 1")
        let encoded = String(decoding: try JSONEncoder().encode(memory), as: UTF8.self)
        #expect(!encoded.contains("PRIVATE-"))
        #expect(!encoded.contains("/Users/"))
    }

    @Test
    func unavailableMalformedOrAmbiguousMemoryNeverInfersSlotsFromModel() async throws {
        for json in ["invalid", "[]", #"{"SPMemoryDataType":[]}"#,
                     #"{"SPMemoryDataType":[{"_items":{} }]}"#,
                     #"{"SPMemoryDataType":[{"_items":[null]}]}"#,
                     #"{"SPMemoryDataType":[{"_items":[]},{"_items":[]}]}"#] {
            let memory = try await collect(output: CommandOutput(command: .memorySlots, stdout: json))
            #expect(memory.slots.isEmpty)
            #expect(memory.section.items.allSatisfy { $0.status == .unknown })
        }
    }

    @Test
    func failureTimeoutAndTruncationDoNotUsePartialInventory() async throws {
        let json = #"{"SPMemoryDataType":[{"global_ecc_state":"ecc_enabled","_items":[{"_name":"DIMM1","dimm_size":"16 GB","dimm_status":"ok"}]}]}"#
        let outputs = [
            CommandOutput(command: .memorySlots, stdout: json, stderr: "PRIVATE-STDERR", exitCode: 1),
            CommandOutput(command: .memorySlots, stdout: json, stderr: "PRIVATE-STDERR", exitCode: nil, termination: .timedOut),
            CommandOutput(command: .memorySlots, stdout: json, outputWasTruncated: true)
        ]
        for output in outputs {
            let memory = try await collect(output: output)
            #expect(memory.slots.isEmpty)
            #expect(memory.section.items.allSatisfy { $0.status == .unknown })
            let encoded = String(decoding: try JSONEncoder().encode(memory), as: UTF8.self)
            #expect(!encoded.contains("PRIVATE-STDERR"))
        }
    }

    @Test
    func successfulEmptySlotArrayDoesNotInferPhysicalSlotCount() async throws {
        let memory = try await collect(group: ["_items": []])
        #expect(memory.slots.isEmpty)
        #expect(memory.section.item("memory-slotCount")?.value == "0")
        #expect(memory.section.item("memory-slotCount")?.message.contains("firmware omitted") == true)
        #expect(memory.section.item("memory-ecc")?.status == .unknown)
    }

    @Test
    func oldHardwareSnapshotsDecodeWithoutMemoryInventory() throws {
        let original = HardwareInfo(section: .init(id: "hardware", title: "Hardware", items: []), gpus: [])
        let data = try JSONEncoder().encode(original)
        var dictionary = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dictionary.removeValue(forKey: "memory")
        let oldData = try JSONSerialization.data(withJSONObject: dictionary)
        let decoded = try JSONDecoder().decode(HardwareInfo.self, from: oldData)
        #expect(decoded.memory == nil)
    }

    private func collect(group: [String: Any]) async throws -> MemoryInfo {
        let data = try JSONSerialization.data(withJSONObject: ["SPMemoryDataType": [group]])
        return try await collect(output: CommandOutput(command: .memorySlots, stdout: String(decoding: data, as: UTF8.self)))
    }

    private func collect(output: CommandOutput) async throws -> MemoryInfo {
        let hardware = await HardwareCollector(runner: MemoryFixtureRunner(output: output)).collect()
        return try #require(hardware.memory)
    }
}

private struct MemoryFixtureRunner: CommandExecuting {
    let output: CommandOutput
    func run(_ command: DiagnosticCommand) async -> CommandOutput {
        command == .memorySlots ? output : CommandOutput(command: command, exitCode: 1)
    }
}
