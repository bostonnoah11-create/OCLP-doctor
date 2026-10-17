import Foundation

public enum DemoModel: String, CaseIterable, Sendable {
    case macPro, macBookPro, unavailable
}

public enum DemoData {
    public static func snapshot(model: DemoModel) -> SystemInfo {
        let isPro = model == .macPro
        let unavailable = model == .unavailable
        func item(_ id: String, _ label: String, _ value: String?,
                  _ status: DiagnosticStatus = .healthy, _ message: String = "Synthetic fixture; not a measurement from a real device.") -> DiagnosticItem {
            DiagnosticItem(id: id, label: label, value: unavailable ? nil : value,
                status: unavailable ? .unknown : status,
                message: unavailable ? "Synthetic example for verifying the UI and report when collection fails." : message,
                evidence: [Evidence(source: "Synthetic fixture", detail: model.rawValue)])
        }
        let hw = DiagnosticSection(id: "hardware", title: "Hardware", items: [
            item("modelName", "Mac Model Name", isPro ? "Mac Pro" : "MacBook Pro"),
            item("modelIdentifier", "macOS Model Identifier", isPro ? "MacPro6,1" : "MacBookPro11,3"),
            item("cpu", "CPU", isPro ? "Intel Xeon E5 (synthetic example)" : "Intel Core i7 Haswell (synthetic example)"),
            item("physicalCores", "Physical Cores", isPro ? "12" : "4"),
            item("logicalCores", "Logical Cores", isPro ? "24" : "8"),
            item("memory", "RAM", isPro ? "64 GB" : "16 GB (example value)"),
            item("gpuCount", "Detected GPU Count", "2")
        ])
        let names = isPro ? ["AMD FirePro D500", "AMD FirePro D500"] : ["Intel Iris Pro", "NVIDIA GeForce GT 750M"]
        let gpus = unavailable ? [] : names.enumerated().map { index, name in
            GPUInfo(id: "gpu-\(index)", name: item("gpu-\(index)-model", "GPU Model", name),
                vram: item("gpu-\(index)-vram", "VRAM", isPro ? "3 GB" : (index == 0 ? "1536 MB (shared)" : "2 GB")),
                metal: item("gpu-\(index)-metal", "Metal Information", "Support reported (synthetic example)", .healthy,
                    "Example of a value reported by an API. Actual graphics acceleration is not verified."))
        }
        return SystemInfo(capturedAt: Date(), duration: 0, hardware: HardwareInfo(section: hw, gpus: gpus),
            os: DiagnosticSection(id: "os", title: "macOS", items: [
                item("productName", "Operating System Name", "macOS"),
                item("productVersion", "Product Version", "26.x (synthetic example)"),
                item("buildVersion", "Build Number", nil, .unknown, "Not specified in this example."),
                item("architecture", "Architecture", "x86_64"),
                item("bootMode", "Boot Mode", nil, .unknown, "No supporting evidence is provided in this example.")
            ]),
            boot: DiagnosticSection(id: "boot", title: "OpenCore / OCLP boot", items: [
                item("openCoreVersion", "OpenCore Version", nil, .unknown, "An installed app alone does not identify the current bootloader."),
                item("oclpBootVersion", "OCLP Version Used to Build EFI", "3.0.0 RC (synthetic example)", .healthy, "Example distinguishing an NVRAM observation from the app version.")
            ]),
            security: DiagnosticSection(id: "security", title: "Security", items: [
                item("sip", "SIP", "custom configuration (synthetic example)", .healthy, "This configuration may be required by OCLP patches and is not, by itself, classified as an error."),
                item("fileVault", "FileVault", nil, .unknown, "No supporting evidence is provided in this example."),
                item("bootArgs", "boot-args", "-v keepsyms=1 (synthetic example)")
            ]),
            patches: DiagnosticSection(id: "patches", title: "Patches", items: [
                item("installedOCLP", "Installed OCLP App", "3.0.0 RC (synthetic example)"),
                item("rootPatchState", "Root Patch Validity", nil, .unknown,
                     "Metadata alone does not establish that current drivers and graphics acceleration are working correctly.")
            ]), isDemo: true, sleepWake: DemoSleepWake.report(unavailable: unavailable))
    }
}
