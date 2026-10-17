import Foundation

public struct OSCollector: Sendable {
    private let runner: any CommandExecuting

    public init(runner: any CommandExecuting) { self.runner = runner }

    public func collect() async -> DiagnosticSection {
        async let nameTask = runner.run(.osName)
        async let versionTask = runner.run(.osVersion)
        async let buildTask = runner.run(.osBuild)
        async let architectureTask = runner.run(.architecture)
        async let softwareTask = runner.run(.software)
        let (name, version, build, architecture, software) = await (
            nameTask, versionTask, buildTask, architectureTask, softwareTask
        )

        return DiagnosticSection(id: "os", title: "macOS", items: [
            Self.item("productName", "Operating System", Self.clean(name.text), name, field: "productName"),
            Self.item("productVersion", "macOS Version", Self.version(version.text), version, field: "productVersion"),
            Self.item("buildVersion", "Build Number", Self.build(build.text), build, field: "buildVersion"),
            Self.item("architecture", "System Architecture", Self.architecture(architecture.text), architecture,
                      field: "uname -m", message: "System architecture reported by the current execution environment."),
            Self.item("bootMode", "Boot Mode", Self.bootMode(software), software,
                      field: "SPSoftwareDataType.boot_mode",
                      message: "Boot mode reported by System Profiler. It does not establish whether OpenCore is in use.")
        ])
    }

    private static func clean(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= 128,
              text.rangeOfCharacter(from: .controlCharacters) == nil,
              !["unknown", "n/a", "not available", "unavailable", "null", "(null)"].contains(text.lowercased()) else { return nil }
        return text
    }

    private static func version(_ value: String?) -> String? {
        guard let text = clean(value), text.range(of: "^[0-9]+(\\.[0-9]+){1,3}$", options: .regularExpression) != nil else { return nil }
        return text
    }

    private static func build(_ value: String?) -> String? {
        guard let text = clean(value), text.range(of: "^[0-9]+[A-Za-z][0-9]+[A-Za-z]?$", options: .regularExpression) != nil else { return nil }
        return text
    }

    private static func architecture(_ value: String?) -> String? {
        guard let text = clean(value), ["x86_64", "i386", "arm64", "arm64e"].contains(text) else { return nil }
        return text
    }

    private static func bootMode(_ output: CommandOutput) -> String? {
        guard let text = output.text, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let rows = dictionary["SPSoftwareDataType"] as? [[String: Any]], rows.count == 1,
              let mode = clean(rows.first?["boot_mode"] as? String) else { return nil }
        switch mode {
        case "normal_boot": return "Normal Boot (normal_boot)"
        case "safe_boot": return "Safe Boot (safe_boot)"
        default: return mode
        }
    }

    private static func item(_ id: String, _ label: String, _ value: String?, _ output: CommandOutput,
                             field: String, message: String = "Operating system information reported by the system.") -> DiagnosticItem {
        DiagnosticItem(id: id, label: label, value: value,
                       message: value == nil ? "The value could not be confirmed. The command may have failed, access may be restricted, or the output may omit this field." : message,
                       evidence: [output.evidence, Evidence(source: output.command.source, detail: "field=\(field)")])
    }
}
