import Foundation

public struct OpenCoreCollector: Sendable {
    private let runner: any CommandExecuting
    public init(runner: any CommandExecuting) { self.runner = runner }

    public func collect() async -> DiagnosticSection {
        async let openCore = runner.run(.openCoreVersion)
        async let oclp = runner.run(.oclpVersion)
        async let settings = runner.run(.oclpSettings)
        let results = await (openCore, oclp, settings)
        return DiagnosticSection(id: "boot", title: "OpenCore · Boot Evidence", items: [
            openCoreItem(results.0), oclpItem(results.1), settingsItem(results.2)
        ])
    }

    private func openCoreItem(_ output: CommandOutput) -> DiagnosticItem {
        let raw = NVRAMValue.string(output)
        if raw == "UNK-000-0000-00-00" {
            return DiagnosticItem(id: "openCoreVersion", label: "Boot OpenCore Version", value: raw,
                status: .unknown, message: "The OpenCore version is hidden. Its version and boot configuration could not be confirmed.", evidence: [output.evidence])
        }
        let version = raw.flatMap { SafeObservation.matches($0, #"^(REL|DBG|NOOPT)-[0-9]{3,6}-[0-9]{4}-[0-9]{2}-[0-9]{2}$"#) ? $0 : nil }
        return DiagnosticItem(id: "openCoreVersion", label: "Boot OpenCore Version", value: version,
            message: version == nil ? "No exposed version could be confirmed. This does not mean the Mac did not boot through OpenCore." : "Version exposed by OpenCore in NVRAM. This is not an inventory of every EFI installation on disk.",
            evidence: [output.evidence])
    }

    private func oclpItem(_ output: CommandOutput) -> DiagnosticItem {
        let version = NVRAMValue.string(output).flatMap(SafeObservation.version)
        return DiagnosticItem(id: "oclpBootVersion", label: "OCLP Version Used to Build EFI", value: version,
            message: version == nil ? "The OCLP version used to build the EFI could not be confirmed. This does not establish boot status or prove that OCLP is absent." : "OCLP-Version from NVRAM identifies the version that built the EFI. It may differ from the installed app and recorded root patch versions.",
            evidence: [output.evidence])
    }

    private func settingsItem(_ output: CommandOutput) -> DiagnosticItem {
        let raw = NVRAMValue.string(output)
        let allowed: Set<String> = ["-allow_fv", "-allow_amfi"]
        let value = raw.map { text -> String in
            let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
            var safe = tokens.filter { allowed.contains($0) }
            if safe.count != tokens.count { safe.append("[redacted]") }
            return safe.isEmpty ? "None" : safe.joined(separator: " ")
        }
        return DiagnosticItem(id: "oclpSettings", label: "OCLP Boot Settings Evidence", value: value,
            message: "Only recognized OCLP tokens are shown. They do not describe all GUI settings or the current behavior of security features.", evidence: [output.evidence])
    }
}

/// Parses only the exact requested NVRAM variable. Never returns stderr or other keys.
enum NVRAMValue {
    static func bytes(_ output: CommandOutput) -> Data? {
        guard output.succeeded, let key = output.command.arguments.last else { return nil }
        let text = output.stdout.trimmingCharacters(in: .newlines)
        guard text.hasPrefix(key) else { return nil }
        let suffix = text.dropFirst(key.count)
        guard let first = suffix.first, first == "\t" || first == " " else { return nil }
        // nvram separates name/value with one tab. Do not strip payload bytes such as 0x20.
        let encoded = suffix.dropFirst()
        let input = Array(encoded.utf8)
        var result = [UInt8]()
        var index = 0
        while index < input.count {
            if input[index] == 37 {
                guard index + 2 < input.count,
                      let high = hex(input[index + 1]), let low = hex(input[index + 2]) else { return nil }
                result.append(high * 16 + low)
                index += 3
            } else {
                result.append(input[index])
                index += 1
            }
        }
        return Data(result)
    }

    static func string(_ output: CommandOutput) -> String? {
        guard let data = bytes(output), let raw = String(data: data, encoding: .utf8) else { return nil }
        let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\t" }) else { return nil }
        return value
    }

    private static func hex(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }
}

enum SafeObservation {
    static func matches(_ value: String, _ pattern: String) -> Bool {
        guard value.utf8.count <= 256 else { return false }
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    static func version(_ raw: String) -> String? {
        let value = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        return matches(value, #"^[0-9]{1,3}(\.[0-9]{1,3}){1,3}([.-](dev|alpha|beta|rc)[0-9]{0,3})?$"#) ? value : nil
    }
}
