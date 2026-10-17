import Foundation
import CoreFoundation

/// Observes the hardware exposed to macOS. This intentionally has no model-to-specification database.
public struct HardwareCollector: Sendable {
    private let runner: any CommandExecuting

    public init(runner: any CommandExecuting) { self.runner = runner }

    public func collect() async -> HardwareInfo {
        async let hardwareTask = runner.run(.hardware)
        async let modelTask = runner.run(.modelIdentifier)
        async let originalModelTask = runner.run(.originalModelIdentifier)
        async let displaysTask = runner.run(.displays)
        async let cpuTask = runner.run(.cpu)
        async let physicalTask = runner.run(.physicalCores)
        async let logicalTask = runner.run(.logicalCores)
        async let memoryTask = runner.run(.memory)
        async let memorySlotsTask = runner.run(.memorySlots)
        let (hardware, model, originalModel, displays, cpu, physical, logical, memory, memorySlots) = await (
            hardwareTask, modelTask, originalModelTask, displaysTask, cpuTask, physicalTask, logicalTask, memoryTask, memorySlotsTask
        )

        let hardwareRows = Self.rows(in: hardware, type: "SPHardwareDataType")
        // Multiple hardware summaries are ambiguous; do not silently select a machine.
        let machine = hardwareRows?.count == 1 ? hardwareRows?.first : nil
        let displayRows = Self.rows(in: displays, type: "SPDisplaysDataType")
        let modelNote = "Model reported by macOS. OpenCore/OCLP spoofing may affect this value; it does not establish the original hardware model."
        let profilerModel = ModelIdentity.validIdentifier(Self.field(machine, "machine_model"))
        let modelItem: DiagnosticItem
        if let profilerModel {
            modelItem = Self.item("modelIdentifier", "Model Identifier", profilerModel, hardware,
                                  field: "SPHardwareDataType.machine_model", message: modelNote)
        } else {
            let value = ModelIdentity.validIdentifier(model.text)
            modelItem = DiagnosticItem(
                id: "modelIdentifier", label: "Model Identifier", value: value,
                message: value == nil
                    ? "Neither System Profiler nor sysctl provided a model identifier. \(modelNote)"
                    : "System Profiler did not provide a value, so the observed sysctl hw.model value is shown. \(modelNote)",
                evidence: [hardware.evidence,
                           Evidence(source: hardware.command.source, detail: "SPHardwareDataType.machine_model unavailable or ambiguous"),
                           model.evidence,
                           Evidence(source: model.command.source, detail: "field=hw.model")]
            )
        }
        let originalValue = ModelIdentity.validIdentifier(NVRAMValue.string(originalModel))
        let originalItem = DiagnosticItem(id: "originalModelIdentifier", label: "Preserved Firmware Model", value: originalValue,
            message: originalValue == nil
                ? "No valid preserved firmware model was available from oem-product. An absent, inaccessible, or invalid value does not establish whether model spoofing is in use."
                : "Model identifier preserved in firmware as oem-product by OpenCore/OCLP. This value may be stale or customized; it is preserved firmware evidence, not authenticated verification of physical or factory identity.",
            evidence: [originalModel.evidence, Evidence(source: originalModel.command.source, detail: "field=oem-product; validated model identifier only")])
        let spoofingValue: String?
        let spoofingMessage: String
        if let originalValue, let reportedValue = modelItem.value {
            let differs = originalValue != reportedValue
            spoofingValue = differs ? "Detected" : "Not detected"
            spoofingMessage = differs
                ? "Preserved firmware model: \(originalValue). macOS-exposed model: \(reportedValue). The identifiers differ, providing evidence of model spoofing. This does not validate either identifier against physical hardware or establish why it was configured. Spoofing is not classified as an error."
                : "Preserved firmware and macOS-exposed model identifiers both report \(reportedValue). Model spoofing was not detected by this comparison; other identity changes or modified firmware values are not excluded."
        } else {
            spoofingValue = nil
            spoofingMessage = "A valid preserved firmware model and a valid macOS-exposed model are both required. One or both are unavailable, so this comparison cannot determine whether model spoofing is in use."
        }
        let spoofingItem = DiagnosticItem(id: "modelSpoofing", label: "Model Spoofing", value: spoofingValue,
            message: spoofingMessage, evidence: originalItem.evidence + modelItem.evidence)
        let items = [
            Self.item("modelName", "Mac Model Name", Self.field(machine, "machine_name"), hardware,
                      field: "SPHardwareDataType.machine_name", message: modelNote),
            modelItem,
            originalItem,
            spoofingItem,
            Self.item("cpu", "CPU", Self.clean(cpu.text), cpu, field: "machdep.cpu.brand_string"),
            Self.item("physicalCores", "Physical Cores", Self.positiveInteger(physical.text), physical,
                      field: "hw.physicalcpu"),
            Self.item("logicalCores", "Logical Cores", Self.positiveInteger(logical.text), logical,
                      field: "hw.logicalcpu"),
            Self.item("memory", "Total RAM", Self.memoryValue(memory.text), memory, field: "hw.memsize"),
            Self.item("gpuCount", "Reported GPU Count", displayRows.map { String($0.count) }, displays,
                      field: "SPDisplaysDataType record count",
                      message: "Number of graphics device records reported by System Profiler. This count cannot establish whether any physical devices are missing.")
        ]
        let gpus = (displayRows ?? []).enumerated().map { index, row in
            let id = "gpu-\(index)"
            let vram = Self.firstField(row, keys: ["spdisplays_vram", "spdisplays_vram_shared"])
            let metal = Self.firstField(row, keys: ["spdisplays_mtlgpufamilysupport", "spdisplays_metal", "spdisplays_metal_supported", "spdisplays_metalfamily", "spdisplays_metal_family"])
            return GPUInfo(
                id: id,
                name: Self.item("\(id)-model", "GPU Model", Self.field(row, "sppci_model"), displays,
                                field: "SPDisplaysDataType[\(index)].sppci_model"),
                vram: Self.item("\(id)-vram", "VRAM / Shared Memory", vram?.value, displays,
                                field: "SPDisplaysDataType[\(index)].\(vram?.key ?? "spdisplays_vram / spdisplays_vram_shared")",
                                message: "Memory reported by macOS. Shared memory does not represent dedicated VRAM capacity."),
                metal: Self.item("\(id)-metal", "Reported Metal Information", metal.map { Self.metalDescription($0.value) }, displays,
                                 field: "SPDisplaysDataType[\(index)].\(metal?.key ?? "Metal field unavailable")",
                                 message: "Metal information reported by System Profiler. It does not verify graphics acceleration, stability, or successful root patch application.")
            )
        }
        return HardwareInfo(section: DiagnosticSection(id: "hardware", title: "Hardware", items: items),
                            gpus: gpus, memory: Self.memoryInfo(memorySlots))
    }

    private static func memoryInfo(_ output: CommandOutput) -> MemoryInfo {
        let groups = output.outputWasTruncated ? nil : rows(in: output, type: "SPMemoryDataType")
        // A single known summary shape is required. Missing, mixed or future shapes stay Unknown.
        let group = groups?.count == 1 ? groups?.first : nil
        let records = group?["_items"] as? [[String: Any]]
        let ecc: String?
        switch field(group, "global_ecc_state") {
        case "ecc_enabled": ecc = "Enabled"
        case "ecc_disabled": ecc = "Disabled"
        default: ecc = nil
        }
        let summary = DiagnosticSection(id: "memory", title: "RAM · Reported Slots and ECC", items: [
            memoryItem("memory-ecc", "Reported ECC Mode", ecc, output, field: "SPMemoryDataType[0].global_ecc_state",
                message: "ECC mode reported by System Profiler. Missing evidence does not mean ECC is disabled. A memory type label or Mac model is not used to infer this mode."),
            memoryItem("memory-slotCount", "Reported Memory Slot Records", records.map { String($0.count) }, output,
                field: "SPMemoryDataType[0]._items record count",
                message: "Number of slot records in the report, including any reported empty slots. This is not an inventory of slots that firmware omitted."),
            memoryItem("memory-eccAssessment", "RAM / ECC Health Assessment", nil, output,
                field: "System Profiler snapshot limitations",
                message: "Not assessed by this read-only snapshot. Reported OK and a zero correctable-error count do not prove error-free RAM. Live ECC rates, counter reset periods and uncorrectable-error coverage are not established; no memory test is run.")
        ])
        let slots = (records ?? []).enumerated().map { index, row in
            let id = "memory-slot-\(index)"
            let location = memorySlotLabel(field(row, "_name"))
            let base = "SPMemoryDataType[0]._items[\(index)]"
            let status: (value: String?, state: DiagnosticStatus)
            switch field(row, "dimm_status") {
            case "ok": status = ("OK", .healthy)
            case "empty": status = ("Empty", .healthy)
            case "mapped_out": status = ("Mapped Out", .attention)
            case "ecc_errors": status = ("ECC Errors Reported", .attention)
            default: status = (nil, .unknown)
            }
            let correctableErrors = memoryErrorCount(row["dimm_ecc_errors"])
            let errorState: DiagnosticStatus = correctableErrors == nil ? .unknown : correctableErrors == "0" ? .healthy : .attention
            let slotItems = [
                memoryItem("\(id)-location", "Reported Slot", location, output, field: base + "._name",
                    message: "Slot label reported by System Profiler. Unrecognized labels are withheld; no location is inferred from a model."),
                memoryItem("\(id)-size", "Reported Capacity", memoryCapacity(field(row, "dimm_size")), output, field: base + ".dimm_size"),
                memoryItem("\(id)-type", "Reported Memory Type", memoryType(field(row, "dimm_type")), output, field: base + ".dimm_type",
                    message: "Memory type reported for this slot. An ECC type label alone does not establish the system ECC mode or error-free operation."),
                memoryItem("\(id)-speed", "Reported Speed", memorySpeed(field(row, "dimm_speed")), output, field: base + ".dimm_speed"),
                memoryItem("\(id)-status", "Reported Slot Status", status.value, output, field: base + ".dimm_status", status: status.state,
                    message: "System Profiler's slot-status snapshot. Mapped Out or ECC Errors Reported warrants review of this evidence, but its cause and current impact are not established. OK is not a memory test result."),
                memoryItem("\(id)-correctableECCErrors", "Reported ECC Correctable Errors", correctableErrors, output,
                    field: base + ".dimm_ecc_errors", status: errorState,
                    message: "Only an explicitly reported nonnegative count is shown. It is a System Profiler snapshot, not a live ECC rate; its reset period and uncorrectable-error coverage are unknown. A missing value does not mean zero errors.")
            ]
            return MemorySlotInfo(id: id, section: DiagnosticSection(id: id, title: "RAM · \(location ?? "Slot record \(index + 1)")", items: slotItems))
        }
        return MemoryInfo(section: summary, slots: slots)
    }

    private static func memorySlotLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        if value == "built-in" { return "Built-in" }
        let component = #"(?:DIMM|BANK|SLOT|CHANNEL)[ _-]?(?:[A-Z]?[0-9]{1,3}|[A-Z])"#
        return SafeObservation.matches(value, "(?i)^\(component)(?:[ /_-]+\(component))*$") ? value : nil
    }

    private static func memoryCapacity(_ value: String?) -> String? {
        guard let value else { return nil }
        if value.lowercased() == "empty" { return "Empty" }
        return SafeObservation.matches(value, #"^[1-9][0-9]{0,5}(\.[0-9]{1,3})? (KB|MB|GB|TB)$"#) ? value : nil
    }

    private static func memoryType(_ value: String?) -> String? {
        guard let value,
              SafeObservation.matches(value, #"^(?:DDR[2-5]?|LPDDR[2-5]X?|SDRAM)(?: SDRAM)?(?: ECC)?$"#) else { return nil }
        return value
    }

    private static func memorySpeed(_ value: String?) -> String? {
        guard let value,
              SafeObservation.matches(value, #"^[1-9][0-9]{0,5}(\.[0-9]{1,3})? (MHz|MT/s)$"#) else { return nil }
        return value
    }

    private static func memoryErrorCount(_ raw: Any?) -> String? {
        let text: String?
        if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            text = number.stringValue
        } else {
            text = raw as? String
        }
        guard let text, SafeObservation.matches(text, #"^[0-9]{1,20}$"#), let count = UInt64(text) else { return nil }
        return String(count)
    }

    private static func memoryItem(_ id: String, _ label: String, _ value: String?, _ output: CommandOutput,
                                   field: String, status: DiagnosticStatus = .healthy,
                                   message: String = "Value reported by System Profiler. This observation does not establish memory health.") -> DiagnosticItem {
        DiagnosticItem(id: id, label: label, value: value, status: status,
            message: value == nil ? "No recognized value was available. \(message)" : message,
            evidence: [output.evidence, Evidence(source: output.command.source, detail: "field=\(field)")])
    }

    private static func rows(in output: CommandOutput, type: String) -> [[String: Any]]? {
        guard let text = output.text, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let rows = dictionary[type] as? [[String: Any]] else { return nil }
        return rows
    }

    private static func clean(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= 256,
              text.rangeOfCharacter(from: .controlCharacters) == nil,
              !["unknown", "n/a", "not available", "unavailable", "null", "(null)"].contains(text.lowercased()) else { return nil }
        return text
    }

    private static func field(_ row: [String: Any]?, _ key: String) -> String? {
        clean(row?[key] as? String)
    }

    private static func firstField(_ row: [String: Any], keys: [String]) -> (key: String, value: String)? {
        for key in keys {
            if let value = field(row, key) { return (key, value) }
        }
        return nil
    }

    private static func positiveInteger(_ value: String?) -> String? {
        guard let text = clean(value), text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let count = UInt64(text), count > 0 else { return nil }
        return String(count)
    }

    private static func memoryValue(_ value: String?) -> String? {
        guard let text = positiveInteger(value), let bytes = UInt64(text) else { return nil }
        let gib: UInt64 = 1_073_741_824
        if bytes.isMultiple(of: gib) { return "\(bytes / gib) GiB (\(bytes) bytes)" }
        return "\(bytes) bytes"
    }

    private static func metalDescription(_ raw: String) -> String {
        switch raw {
        case "spdisplays_metal2": return "Metal 2 (spdisplays_metal2)"
        case "spdisplays_metal3": return "Metal 3 (spdisplays_metal3)"
        case "spdisplays_metal4": return "Metal 4 (spdisplays_metal4)"
        case "spdisplays_supported", "spdisplays_metal_supported", "spdisplays_yes": return "Supported (\(raw))"
        case "spdisplays_unsupported", "spdisplays_metal_unsupported", "spdisplays_no": return "Not supported (\(raw))"
        default: return raw
        }
    }

    private static func item(_ id: String, _ label: String, _ value: String?, _ output: CommandOutput,
                             field: String, message: String = "Value observed from macOS. It does not guarantee that the entire component is functioning correctly.") -> DiagnosticItem {
        DiagnosticItem(id: id, label: label, value: value,
                       message: value == nil ? "The value could not be confirmed. The command may have failed, access may be restricted, or the output format may be unsupported. No value was inferred from model specifications." : message,
                       evidence: [output.evidence, Evidence(source: output.command.source, detail: "field=\(field)")])
    }
}
