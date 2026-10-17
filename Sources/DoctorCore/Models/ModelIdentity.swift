import Foundation

/// Presentation of observed model identifiers, never a model-to-specification lookup.
public enum ModelIdentity {
    public static func validIdentifier(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.utf8.count <= 64,
              value.range(of: #"^(?:MacPro|MacBookPro|MacBookAir|MacBook|Macmini|MacStudio|iMacPro|iMac|Mac|Xserve)[0-9]{1,3},[0-9]{1,3}$"#, options: .regularExpression) != nil else { return nil }
        return value
    }

    public static func displayName(_ identifier: String) -> String {
        guard let valid = validIdentifier(identifier), let number = valid.firstIndex(where: \.isNumber) else { return identifier }
        let family = String(valid[..<number])
        let names = ["MacPro": "Mac Pro", "MacBookPro": "MacBook Pro", "MacBookAir": "MacBook Air",
            "MacBook": "MacBook", "Macmini": "Mac mini", "MacStudio": "Mac Studio",
            "iMacPro": "iMac Pro", "iMac": "iMac", "Mac": "Mac", "Xserve": "Xserve"]
        return "\(names[family] ?? family) \(valid[number...])"
    }
}

public extension HardwareInfo {
    var overviewModelTitle: String {
        guard let reported = ModelIdentity.validIdentifier(section.item("modelIdentifier")?.value) else {
            return section.item("modelName")?.value ?? "Unknown Mac"
        }
        let original = ModelIdentity.validIdentifier(section.item("originalModelIdentifier")?.value)
        let suffix = original.map { $0 != reported ? " (spoofed)" : "" } ?? ""
        return ModelIdentity.displayName(reported) + suffix
    }

    var overviewModelNote: String {
        guard let reported = ModelIdentity.validIdentifier(section.item("modelIdentifier")?.value) else {
            return "Model identifier unavailable. Model spoofing status is unknown."
        }
        guard let original = ModelIdentity.validIdentifier(section.item("originalModelIdentifier")?.value) else {
            return "Reported by macOS. Model spoofing status is unknown because the original model could not be verified."
        }
        if reported != original {
            return "Preserved firmware model: \(ModelIdentity.displayName(original)). macOS reports \(ModelIdentity.displayName(reported))."
        }
        return "The reported and preserved firmware model identifiers match."
    }
}
