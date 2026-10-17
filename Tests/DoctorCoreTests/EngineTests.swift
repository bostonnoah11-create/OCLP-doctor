import Foundation
import Testing
@testable import DoctorCore

@Suite
struct EngineTests {
    @Test func testEveryCollectorCanFailWithoutFailingTheReport() async {
        let runner = FailingRunner()
        let engine = DiagnosticEngine(runner: runner, reader: UnreadableFiles(),
            diagnosticReports: DiagnosticReportCollector(reader: UnreadableDiagnosticReports()))
        let snapshot = await engine.collect()
        let commands = await runner.observed()
        // A failed power-history query supplies no Wake anchor; do not invent a date window.
        let expected = DiagnosticCommand.allCases.filter { $0 != .wakeIncidentLog && $0 != .wakeBluetoothLog && $0 != .wakeBluetoothLifecycleLog }
        #expect(Set(commands) == Set(expected))
        #expect(commands.count == expected.count)
        #expect(!(snapshot.isDemo))
        #expect(snapshot.items.allSatisfy { $0.status == .unknown })
        #expect(snapshot.items.allSatisfy { !$0.evidence.isEmpty })
        let report = ReportGenerator.generate(snapshot)
        #expect(report.contains("Unknown"))
        #expect(report.contains("timedOut"))
        #expect(!(report.contains("PRIVATE")))
        #expect(snapshot.duration >= 0)
    }
}

private struct UnreadableDiagnosticReports: DiagnosticReportReading {
    func read(since: Date, until: Date) -> DiagnosticReportReadBatch {
        DiagnosticReportReadBatch(readableDirectories: 0, unreadableDirectories: 2)
    }
}

private actor FailingRunner: CommandExecuting {
    private var commands = [DiagnosticCommand]()
    func run(_ command: DiagnosticCommand) async -> CommandOutput {
        commands.append(command)
        return CommandOutput(command: command, stdout: "PRIVATE", stderr: "PRIVATE",
                             exitCode: nil, termination: .timedOut)
    }
    func observed() -> [DiagnosticCommand] { commands }
}

private struct UnreadableFiles: FileReading {
    func read(_ url: URL, maxBytes: Int) -> FileReadOutcome { .unreadable }
    func canonicalURL(for url: URL) -> URL { url }
}
