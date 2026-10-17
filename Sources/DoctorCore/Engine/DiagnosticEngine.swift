import Foundation

/// Phase 1 collects observations only. There is intentionally no recovery engine.
public struct DiagnosticEngine: Sendable {
    private let runner: any CommandExecuting
    private let reader: any FileReading
    private let diagnosticReports: DiagnosticReportCollector

    public init(runner: any CommandExecuting = CommandRunner(), reader: any FileReading = LocalFileReader(),
                diagnosticReports: DiagnosticReportCollector = DiagnosticReportCollector()) {
        self.runner = runner
        self.reader = reader
        self.diagnosticReports = diagnosticReports
    }

    public func collect() async -> SystemInfo {
        let date = Date()
        let start = ProcessInfo.processInfo.systemUptime
        async let hardware = HardwareCollector(runner: runner).collect()
        async let os = OSCollector(runner: runner).collect()
        async let boot = OpenCoreCollector(runner: runner).collect()
        async let security = SecurityCollector(runner: runner).collect()
        async let patches = PatchCollector(reader: reader).collect()
        async let sleepWake = SleepWakeCollector(runner: runner, reportCollector: diagnosticReports).collect(now: date)
        let result = await (hardware, os, boot, security, patches, sleepWake)
        return SystemInfo(capturedAt: date, duration: ProcessInfo.processInfo.systemUptime - start,
                          hardware: result.0, os: result.1, boot: result.2,
                          security: result.3, patches: result.4, sleepWake: result.5)
    }
}
