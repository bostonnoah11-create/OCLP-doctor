import AppKit
import DoctorCore
import Foundation

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var snapshot: SystemInfo?
    @Published private(set) var isCollecting = false
    @Published private(set) var report = ""
    @Published private(set) var reportParagraphs: [String] = []
    @Published private(set) var copyMessage: String?

    private let engine = DiagnosticEngine()
    private let demo: DemoModel?
    private let smokeTest: Bool
    private var didStart = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        if arguments.contains("--demo-mac-pro") {
            demo = .macPro
        } else if arguments.contains("--demo-macbook-pro") {
            demo = .macBookPro
        } else if arguments.contains("--demo-unavailable") {
            demo = .unavailable
        } else {
            demo = nil
        }
        smokeTest = arguments.contains("--smoke-test")
    }

    var isDemo: Bool { demo != nil }

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        await refresh()
        if smokeTest {
            // Only smoke-test launches wait here, giving SwiftUI a chance to render the result.
            // A successful smoke test still does not replace manual visual verification.
            try? await Task.sleep(nanoseconds: 500_000_000)
            // A completion marker distinguishes successful collection from an early process exit.
            FileHandle.standardOutput.write(Data("OCLP Doctor: initial diagnostic complete.\n".utf8))
            NSApp.terminate(nil)
        }
    }

    func refresh() async {
        // The main actor serializes this guard, including the initial automatic scan.
        guard !isCollecting else { return }
        isCollecting = true
        copyMessage = nil
        defer { isCollecting = false }

        let next: SystemInfo
        if let demo {
            next = DemoData.snapshot(model: demo)
        } else {
            next = await engine.collect()
        }
        snapshot = next
        report = ReportGenerator.generate(next)
        reportParagraphs = report.components(separatedBy: "\n\n")
    }

    /// Called only by the explicit Copy Report button or its menu command.
    func copyReport() {
        guard snapshot != nil else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setString(report, forType: .string)
        copyMessage = copied ? "Report copied to the clipboard." : "Could not write to the clipboard. Select and copy the report text instead."
    }
}
