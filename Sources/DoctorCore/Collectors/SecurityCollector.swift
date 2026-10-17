import Foundation

public struct SecurityCollector: Sendable {
    private let runner: any CommandExecuting
    public init(runner: any CommandExecuting) { self.runner = runner }

    public func collect() async -> DiagnosticSection {
        async let sip = runner.run(.sip)
        async let fileVault = runner.run(.fileVault)
        async let bootArgs = runner.run(.bootArgs)
        async let csr = runner.run(.csrConfig)
        async let root = runner.run(.authenticatedRoot)
        let results = await (sip, fileVault, bootArgs, csr, root)
        return DiagnosticSection(id: "security", title: "Security · Current Observations", items: [
            statusItem(results.0, id: "sip", label: "SIP", prefix: "System Integrity Protection status:"),
            configurationItem(results.0),
            fileVaultItem(results.1), bootArgsItem(results.2), csrItem(results.3),
            statusItem(results.4, id: "authenticatedRoot", label: "Authenticated Root", prefix: "Authenticated Root status:")
        ])
    }

    private func configurationItem(_ output: CommandOutput) -> DiagnosticItem {
        let labels = ["Apple Internal", "Kext Signing", "Filesystem Protections", "Debugging Restrictions",
                      "DTrace Restrictions", "NVRAM Protections", "BaseSystem Verification", "Kernel Debugging Restrictions",
                      "Untrusted Kexts", "Unrestricted Filesystem", "Task for PID", "Unrestricted DTrace", "Unrestricted NVRAM"]
        let lines = (output.text?.components(separatedBy: .newlines) ?? [])
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let details = labels.compactMap { label -> String? in
            if lines.contains(label + ": enabled") { return label + ": Enabled" }
            if lines.contains(label + ": disabled") { return label + ": Disabled" }
            return nil
        }
        return DiagnosticItem(id: "sipConfiguration", label: "SIP Configuration Details",
            value: details.isEmpty ? nil : details.joined(separator: " · "),
            message: "Only recognized details reported by csrutil are shown. Default configurations may omit detailed output; unrecognized fields are not displayed.", evidence: [output.evidence])
    }

    private func statusItem(_ output: CommandOutput, id: String, label: String, prefix: String) -> DiagnosticItem {
        let line = output.text?.components(separatedBy: .newlines).first
        let value: String?
        switch line {
        case prefix + " enabled.", prefix + " enabled": value = "Enabled"
        case prefix + " disabled.", prefix + " disabled": value = "Disabled"
        case prefix + " unknown (Custom Configuration).": value = "Custom Configuration"
        default: value = nil
        }
        return DiagnosticItem(id: id, label: label, value: value,
            status: value == "Custom Configuration" ? .unknown : .healthy,
            message: "Currently reported setting. OCLP root patches may require reduced protection, so a disabled setting is neither classified as an error nor changed.", evidence: [output.evidence])
    }

    private func fileVaultItem(_ output: CommandOutput) -> DiagnosticItem {
        let line = output.text?.components(separatedBy: .newlines).first
        let value: String?
        switch line {
        case "FileVault is On.": value = "On"
        case "FileVault is Off.": value = "Off"
        default:
            if let line, line.hasPrefix("Encryption in progress:") { value = "Encryption in progress" }
            else if let line, line.hasPrefix("Decryption in progress:") { value = "Decryption in progress" }
            else { value = nil }
        }
        return DiagnosticItem(id: "fileVault", label: "FileVault", value: value,
            message: "Encryption status reported by fdesetup. No settings are changed and no recovery action is performed.", evidence: [output.evidence])
    }

    private func bootArgsItem(_ output: CommandOutput) -> DiagnosticItem {
        let value = NVRAMValue.string(output).map(Self.redactedBootArguments)
        return DiagnosticItem(id: "bootArgs", label: "boot-args", value: value,
            message: "Only reviewed diagnostic flags and specific numeric settings are shown. Unrecognized tokens and potentially private values are redacted.", evidence: [output.evidence])
    }

    static func redactedBootArguments(_ value: String) -> String {
        let flags: Set<String> = ["-v", "-x", "-s", "-lilubetaall", "-no_compat_check", "-nokcmismatchpanic", "-amfipassbeta", "-wegbeta", "-wegnoegpu", "-igfxvesa", "-radvesa", "keepsyms=1", "debug=0x100", "ipc_control_port_options=0", "amfi=0x80", "amfi_get_out_of_my_way=1", "nv_disable=1", "nvda_drv=1", "nvda_drv_vrl=1"]
        let keys: Set<String> = ["keepsyms", "debug", "ipc_control_port_options", "amfi", "amfi_get_out_of_my_way", "nv_disable", "nvda_drv", "nvda_drv_vrl"]
        let tokens = value.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return "None" }
        return tokens.map { token in
            if flags.contains(token) { return token }
            if let separator = token.firstIndex(of: "=") {
                let key = String(token[..<separator])
                if keys.contains(key) { return key + "=[redacted]" }
            }
            return "[redacted]"
        }.joined(separator: " ")
    }

    private func csrItem(_ output: CommandOutput) -> DiagnosticItem {
        var value: String?
        if let data = NVRAMValue.bytes(output), data.count == 4 {
            let bits = data.enumerated().reduce(UInt32(0)) { result, entry in
                result | (UInt32(entry.element) << (entry.offset * 8))
            }
            value = String(format: "0x%08X", bits)
        }
        return DiagnosticItem(id: "csrConfig", label: "csr-active-config (NVRAM)", value: value,
            message: "Four-byte NVRAM value read in little-endian order. It does not by itself establish the full running SIP state or patch compatibility.", evidence: [output.evidence])
    }
}
