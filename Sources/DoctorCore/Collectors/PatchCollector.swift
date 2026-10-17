import Foundation

public struct PatchCollector: Sendable {
    private let reader: any FileReading
    static let metadataURL = URL(fileURLWithPath: "/System/Library/CoreServices/OpenCore-Legacy-Patcher.plist")
    static let appURLs = [
        URL(fileURLWithPath: "/Library/Application Support/Dortania/OpenCore-Patcher.app"),
        URL(fileURLWithPath: "/Applications/OpenCore-Patcher.app")
    ]
    private static let byteLimit = 1_048_576

    public init(reader: any FileReading = LocalFileReader()) { self.reader = reader }

    public func collect() async -> DiagnosticSection {
        var items = installedApplication()
        let outcome = reader.read(Self.metadataURL, maxBytes: Self.byteLimit)
        let evidence = Evidence(source: "/System/Library/CoreServices/OpenCore-Legacy-Patcher.plist",
                                detail: outcome.description)
        guard case .data(let data) = outcome else {
            let value: String
            switch outcome {
            case .missing: value = "No metadata found"
            case .unreadable: value = "Metadata could not be read"
            case .tooLarge: value = "Metadata exceeds size limit"
            case .data: value = "Metadata not confirmed"
            }
            items.append(DiagnosticItem(id: "rootPatchState", label: "Root Patch State", value: value,
                status: .unknown, message: "Current patch validity could not be confirmed. A missing or unreadable record does not prove that the system is unpatched.", evidence: [evidence]))
            return DiagnosticSection(id: "patches", title: "OCLP · Root Patch Records", items: items)
        }
        guard data.count <= Self.byteLimit,
              let dictionary = Self.dictionary(data),
              let version = (dictionary["OpenCore Legacy Patcher"] as? String).flatMap(SafeObservation.version) else {
            items.append(DiagnosticItem(id: "rootPatchState", label: "Root Patch State", value: "Unrecognized metadata format",
                status: .unknown, message: "No plist dictionary with a recognized OCLP version field was found. Patch validity cannot be determined.", evidence: [evidence]))
            return DiagnosticSection(id: "patches", title: "OCLP · Root Patch Records", items: items)
        }
        items.append(DiagnosticItem(id: "rootPatchState", label: "Root Patch State", value: "Metadata found · validity unverified",
            status: .unknown, message: "A patch record was found. Compatibility with the current OS and drivers, complete patch application, and correct operation after reboot have not been verified.", evidence: [evidence]))
        items.append(DiagnosticItem(id: "rootPatchVersion", label: "Root Patch OCLP Version", value: version,
            message: "Patcher version recorded in metadata. It is separate from the installed app and EFI build versions.", evidence: [evidence]))
        let date = (dictionary["Time Patched"] as? String).flatMap(Self.safePatchDate)
        items.append(DiagnosticItem(id: "rootPatchDate", label: "Recorded Patch Time", value: date,
            message: "Local time string recorded by OCLP. It does not establish the time zone or subsequent system changes.", evidence: [evidence]))
        let os = (dictionary["OS Version"] as? String).flatMap { value in
            SafeObservation.matches(value, #"^[0-9]{1,3}\.[0-9]{1,3} \([0-9]{1,3}[A-Z][0-9]{1,6}[a-z]?\)$"#) ? value : nil
        }
        items.append(DiagnosticItem(id: "rootPatchOS", label: "Recorded Darwin Version · OS Build", value: os,
            message: "The leading number is the Darwin version, not the macOS product version. Compatibility with the current OS is not evaluated.", evidence: [evidence]))
        let names = Self.knownPatchNames.filter { dictionary[$0] is [String: Any] }.sorted()
        let hiddenCount = dictionary.keys.filter { !Self.metadataKeys.contains($0) && !Self.knownPatchNames.contains($0) && dictionary[$0] is [String: Any] }.count
        let visible = names.isEmpty ? "No recognized patch names" : names.joined(separator: ", ")
        let patchNames = hiddenCount > 0 ? visible + " · \(hiddenCount) unrecognized names withheld" : visible
        items.append(DiagnosticItem(id: "patchSets", label: "Recorded Patch Sets", value: patchNames,
            status: names.isEmpty ? .unknown : .healthy,
            message: "Only names confirmed in official sources are shown. Internal paths, commands, and unrecognized keys are omitted; actual application is not verified.", evidence: [evidence]))
        return DiagnosticSection(id: "patches", title: "OCLP · Root Patch Records", items: items)
    }

    private func installedApplication() -> [DiagnosticItem] {
        var seen = Set<URL>()
        var versions = Set<String>()
        var identityFound = false
        var evidence = [Evidence]()
        for candidate in Self.appURLs {
            let canonical = reader.canonicalURL(for: candidate)
            guard seen.insert(canonical).inserted else { continue }
            let outcome = reader.read(canonical.appendingPathComponent("Contents/Info.plist"), maxBytes: Self.byteLimit)
            // Fixed source labels prevent a resolved symlink from leaking a private path.
            var detail = outcome.description
            if case .data(let data) = outcome, data.count <= Self.byteLimit,
               let dictionary = Self.dictionary(data),
               dictionary["CFBundleIdentifier"] as? String == "com.dortania.opencore-legacy-patcher" {
                identityFound = true
                let version = (dictionary["CFBundleShortVersionString"] as? String).flatMap(SafeObservation.version)
                    ?? (dictionary["CFBundleVersion"] as? String).flatMap(SafeObservation.version)
                if let version { versions.insert(version); detail = "bundle identifier and version verified" }
                else { detail = "bundle identifier verified; version unrecognized" }
            } else if case .data = outcome {
                detail = "unrecognized bundle metadata"
            }
            evidence.append(Evidence(source: "OCLP application Info.plist (standard location)", detail: detail))
        }
        let presence = DiagnosticItem(id: "installedOCLPPresence", label: "OCLP App Presence Evidence",
            value: identityFound ? "App with matching bundle ID found" : "Not confirmed in standard locations",
            status: identityFound ? .healthy : .unknown,
            message: "Identified by the bundle ID in app metadata. Code signing and app operation are not verified, and other installation locations are not searched.", evidence: evidence)
        let version = DiagnosticItem(id: "installedOCLP", label: "Installed OCLP App Version",
            value: versions.isEmpty ? nil : versions.sorted().joined(separator: " · "),
            message: versions.isEmpty ? "No recognized app version was found in the two standard locations. This does not rule out an app elsewhere or establish whether OCLP is installed." : "The bundle ID and version were confirmed in standard locations. Shortcuts to the same app are counted once, and the app is not launched.", evidence: evidence)
        return [presence, version]
    }

    private static func dictionary(_ data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    private static func safePatchDate(_ text: String) -> String? {
        let months = "January|February|March|April|May|June|July|August|September|October|November|December"
        return SafeObservation.matches(text, "^(\(months)) [0-9]{2}, [0-9]{4} @ [0-9]{2}:[0-9]{2}:[0-9]{2}$") ? text : nil
    }

    private static let metadataKeys: Set<String> = [
        "OpenCore Legacy Patcher", "PatcherSupportPkg", "Time Patched", "Commit URL",
        "Kernel Debug Kit Used", "Metal Library Used", "OS Version", "Custom Signature"
    ]
    // Conservative allowlist; unknown/future names remain private until reviewed.
    private static let knownPatchNames: Set<String> = [
        "Non-Metal Common", "Intel Ivy Bridge", "Intel Haswell", "AMD Legacy GCN", "Nvidia Kepler", "Nvidia Kepler OpenCL",
        "Legacy Wireless", "Legacy Wireless Extended", "Modern Wireless",
        "Modern Wireless Common", "Modern Wireless Extended"
    ]
}
