import AppKit
import SwiftUI

@main
struct OCLPDoctorApp: App {
    @NSApplicationDelegateAdaptor(DoctorApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model = DashboardModel()

    var body: some Scene {
        WindowGroup {
            // The existing window proposes the viewport. Page contents must not
            // contribute a new ideal window size when the sidebar selection changes.
            GeometryReader { viewport in
                DashboardView(model: model)
                    .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
            }
            .frame(minWidth: 1040, minHeight: 720)
        }
        .windowToolbarStyle(UnifiedCompactWindowToolbarStyle(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Diagnostics") {
                Button("Refresh Diagnostics") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isCollecting)

                Button("Copy Report") { model.copyReport() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.snapshot == nil)
            }
        }
    }
}

final class DoctorApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
