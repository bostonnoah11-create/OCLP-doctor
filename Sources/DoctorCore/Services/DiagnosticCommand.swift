import Foundation

/// Closed, read-only command list. No shell, caller-supplied executable, or arbitrary arguments.
public enum DiagnosticCommand: String, CaseIterable, Sendable {
    case hardware, displays, software, memorySlots, modelIdentifier, originalModelIdentifier, cpu, physicalCores, logicalCores, memory
    case osVersion, osBuild, osName, architecture
    case sip, authenticatedRoot, fileVault, bootArgs, csrConfig, openCoreVersion, oclpVersion, oclpSettings
    case powerHistory, sleepWakeLog, sleepWakeRecentLog, wakeIncidentLog, wakeBluetoothLog, wakeBluetoothLifecycleLog

    public var executable: String {
        switch self {
        case .hardware, .displays, .software, .memorySlots: return "/usr/sbin/system_profiler"
        case .modelIdentifier, .cpu, .physicalCores, .logicalCores, .memory: return "/usr/sbin/sysctl"
        case .osVersion, .osBuild, .osName: return "/usr/bin/sw_vers"
        case .architecture: return "/usr/bin/uname"
        case .sip, .authenticatedRoot: return "/usr/bin/csrutil"
        case .fileVault: return "/usr/bin/fdesetup"
        case .powerHistory: return "/usr/bin/pmset"
        case .sleepWakeLog, .sleepWakeRecentLog, .wakeIncidentLog, .wakeBluetoothLog, .wakeBluetoothLifecycleLog: return "/usr/bin/log"
        default: return "/usr/sbin/nvram"
        }
    }
    public var arguments: [String] {
        switch self {
        case .hardware: return ["SPHardwareDataType", "-json", "-detailLevel", "basic"]
        case .displays: return ["SPDisplaysDataType", "-json", "-detailLevel", "basic"]
        case .software: return ["SPSoftwareDataType", "-json", "-detailLevel", "basic"]
        case .memorySlots: return ["SPMemoryDataType", "-json", "-detailLevel", "basic"]
        case .modelIdentifier: return ["-n", "hw.model"]
        case .originalModelIdentifier: return ["4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:oem-product"]
        case .cpu: return ["-n", "machdep.cpu.brand_string"]
        case .physicalCores: return ["-n", "hw.physicalcpu"]
        case .logicalCores: return ["-n", "hw.logicalcpu"]
        case .memory: return ["-n", "hw.memsize"]
        case .osVersion: return ["-productVersion"]
        case .osBuild: return ["-buildVersion"]
        case .osName: return ["-productName"]
        case .architecture: return ["-m"]
        case .sip: return ["status"]
        case .authenticatedRoot: return ["authenticated-root", "status"]
        case .fileVault: return ["status"]
        case .bootArgs: return ["boot-args"]
        case .csrConfig: return ["csr-active-config"]
        case .openCoreVersion: return ["4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version"]
        case .oclpVersion: return ["4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:OCLP-Version"]
        case .oclpSettings: return ["4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:OCLP-Settings"]
        case .powerHistory: return ["-g", "log"]
        case .sleepWakeLog, .sleepWakeRecentLog:
            return ["show", "--style", "ndjson", "--last", self == .sleepWakeRecentLog ? "2h" : "7d", "--timezone", "UTC", "--info", "--predicate", Self.sleepPredicate]
        case .wakeIncidentLog, .wakeBluetoothLog, .wakeBluetoothLifecycleLog:
            // This command is only executed through the validated date-window API.
            return []
        }
    }
    public var timeout: TimeInterval {
        switch self {
        case .displays: return 30
        case .hardware, .software, .memorySlots: return 20
        case .powerHistory: return 20
        case .sleepWakeLog: return 30
        case .sleepWakeRecentLog: return 15
        case .wakeIncidentLog: return 15
        case .wakeBluetoothLog, .wakeBluetoothLifecycleLog: return 35
        default: return 8
        }
    }
    public var source: String { ([executable] + arguments).joined(separator: " ") }
    var keepsOutputTail: Bool { self == .powerHistory || self == .sleepWakeLog || self == .sleepWakeRecentLog || self == .wakeIncidentLog }
    var outputLimit: Int {
        if self == .wakeBluetoothLog { return 64 * 1_048_576 }
        return keepsOutputTail ? 4 * 1_048_576 : 1_048_576
    }

    // Narrow the source before parsing. Graphics candidates still require temporal correlation.
    private static let powerGraphicsPredicate = #"(process == "kernel" OR process == "powerd" OR process == "WindowServer") AND (((eventMessage CONTAINS[c] "sleep" OR eventMessage CONTAINS[c] "wake" OR eventMessage CONTAINS[c] "power state") AND (messageType == 16 OR messageType == 17 OR eventMessage CONTAINS[c] "fail" OR eventMessage CONTAINS[c] "error" OR eventMessage CONTAINS[c] "timed out" OR eventMessage CONTAINS[c] "timeout" OR eventMessage CONTAINS[c] " hang" OR eventMessage CONTAINS[c] "panic")) OR (process == "kernel" AND (eventMessage CONTAINS[c] "GPU" OR eventMessage CONTAINS[c] "AMD" OR eventMessage CONTAINS[c] "IOGraphics" OR eventMessage CONTAINS[c] "framebuffer" OR eventMessage CONTAINS[c] "display" OR eventMessage CONTAINS[c] "IOAccel") AND (messageType == 16 OR messageType == 17 OR eventMessage CONTAINS[c] "fail" OR eventMessage CONTAINS[c] "error" OR eventMessage CONTAINS[c] "timeout" OR eventMessage CONTAINS[c] " hang")))"#
    // A generic "daemon started" message includes unrelated services such as WIPROX.
    // Exact Bluetooth service lifecycle records come from launchd; readiness is separate.
    private static let bluetoothLifecyclePredicate = #"(process == "bluetoothd" AND (eventMessage CONTAINS[c] "HCI" OR eventMessage CONTAINS[c] "controller") AND (eventMessage CONTAINS[c] "ready" OR eventMessage CONTAINS[c] "initialized" OR eventMessage CONTAINS[c] "initialization complete" OR eventMessage CONTAINS[c] "initialization succeeded")) OR (process == "launchd" AND eventMessage CONTAINS[c] "com.apple.bluetoothd")"#
    static let bluetoothFailurePredicate = #"process == "bluetoothd" AND eventMessage CONTAINS[c] "HCI" AND (eventMessage CONTAINS[c] "fail" OR eventMessage CONTAINS[c] "error" OR eventMessage CONTAINS[c] "timeout" OR eventMessage CONTAINS[c] "timed out" OR eventMessage CONTAINS[c] "command disallowed")"#
    // HCI failures have their own bounded query so a flood cannot consume all other sources.
    static let sleepPredicate = "(" + powerGraphicsPredicate + ") OR (" + bluetoothLifecyclePredicate + ")"
    // Prioritize actionable records in the short query. Broad queries retain Fault-level traces.
    static let focusedPredicate = "(" + powerGraphicsPredicate.replacingOccurrences(of: "messageType == 16 OR messageType == 17", with: "messageType == 16") + ")"

    /// Accept only a short, finite UTC interval; never caller-provided predicate or shell text.
    static func wakeIncidentArguments(since: Date, until: Date) -> [String]? {
        let start = since.timeIntervalSince1970, end = until.timeIntervalSince1970
        guard start.isFinite, end.isFinite, start >= 946_684_800, end <= 253_402_300_799,
              start == start.rounded(.down), end == end.rounded(.down),
              end > start, end - start <= 420 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        // --timezone controls output formatting, not interpretation of date arguments.
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
        return ["show", "--style", "ndjson", "--start", formatter.string(from: since), "--end", formatter.string(from: until),
            "--timezone", "UTC", "--info", "--predicate", focusedPredicate]
    }

    static func wakeBluetoothArguments(since: Date, until: Date) -> [String]? {
        guard var args = wakeIncidentArguments(since: since, until: until) else { return nil }
        args[args.count - 1] = bluetoothFailurePredicate
        if let style = args.firstIndex(of: "--style") { args[style + 1] = "compact" }
        return args
    }
    static func wakeBluetoothLifecycleArguments(since: Date, until: Date) -> [String]? {
        guard var args = wakeIncidentArguments(since: since, until: until) else { return nil }
        args[args.count - 1] = bluetoothLifecyclePredicate
        return args
    }
}

public enum CommandTermination: String, Codable, Sendable {
    case completed, timedOut, launchFailed, cancelled, outputLimit
}

public struct CommandOutput: Sendable {
    public let command: DiagnosticCommand
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32?
    public let termination: CommandTermination
    public let outputWasTruncated: Bool
    public let windowStart: Date?
    public let windowEnd: Date?

    public init(command: DiagnosticCommand, stdout: String = "", stderr: String = "",
                exitCode: Int32? = 0, termination: CommandTermination = .completed, outputWasTruncated: Bool = false,
                windowStart: Date? = nil, windowEnd: Date? = nil) {
        self.command = command
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.termination = termination
        self.outputWasTruncated = outputWasTruncated
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }
    public var succeeded: Bool { termination == .completed && exitCode == 0 }
    public var text: String? {
        guard succeeded else { return nil }
        let text = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    public var evidence: Evidence {
        // Do not copy stderr or raw stdout: these can contain usernames and identifiers.
        let source: String
        if let windowStart, let windowEnd {
            let arguments: [String]?
            switch command {
            case .wakeIncidentLog: arguments = DiagnosticCommand.wakeIncidentArguments(since: windowStart, until: windowEnd)
            case .wakeBluetoothLog: arguments = DiagnosticCommand.wakeBluetoothArguments(since: windowStart, until: windowEnd)
            case .wakeBluetoothLifecycleLog: arguments = DiagnosticCommand.wakeBluetoothLifecycleArguments(since: windowStart, until: windowEnd)
            default: arguments = nil
            }
            source = arguments.map { ([command.executable] + $0).joined(separator: " ") } ?? command.source
        } else { source = command.source }
        return Evidence(source: source,
                 detail: "termination=\(termination.rawValue), exit=\(exitCode.map(String.init) ?? "unavailable")\(outputWasTruncated ? ", output=truncated" : "")")
    }
}

public protocol CommandExecuting: Sendable {
    func run(_ command: DiagnosticCommand) async -> CommandOutput
    func runWakeIncidentLog(since: Date, until: Date) async -> CommandOutput
    func runWakeBluetoothLog(since: Date, until: Date) async -> CommandOutput
    func runWakeBluetoothLifecycleLog(since: Date, until: Date) async -> CommandOutput
}

public extension CommandExecuting {
    func runWakeBluetoothLifecycleLog(since: Date, until: Date) async -> CommandOutput {
        CommandOutput(command: .wakeBluetoothLifecycleLog, exitCode: nil, termination: .launchFailed, windowStart: since, windowEnd: until)
    }
    func runWakeIncidentLog(since: Date, until: Date) async -> CommandOutput {
        CommandOutput(command: .wakeIncidentLog, exitCode: nil, termination: .launchFailed, windowStart: since, windowEnd: until)
    }
    func runWakeBluetoothLog(since: Date, until: Date) async -> CommandOutput {
        CommandOutput(command: .wakeBluetoothLog, exitCode: nil, termination: .launchFailed, windowStart: since, windowEnd: until)
    }
}
