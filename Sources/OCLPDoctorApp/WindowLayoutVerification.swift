import AppKit
import SwiftUI

/// Transparent geometry probe used only by the explicit demo verification harness.
struct WindowLayoutProbe: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> WindowLayoutProbeView {
        WindowLayoutProbeView(probeID: id)
    }
    func updateNSView(_ view: WindowLayoutProbeView, context: Context) { view.probeID = id }
}

final class WindowLayoutProbeView: NSView {
    var probeID: String

    init(probeID: String) {
        self.probeID = probeID
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { return nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
enum WindowLayoutVerification {
    private static let probeNames = ["sidebar", "header", "viewport"]
    private static var frameNames: [String] { ["window", "content", "minSize", "contentMinSize"] + probeNames }

    static func run(pages: [String], selectPage: (String) -> Void) async {
        let arguments = ProcessInfo.processInfo.arguments
        let demos = ["--demo-mac-pro", "--demo-macbook-pro", "--demo-unavailable"]
        guard arguments.contains("--verify-window-layout"), demos.contains(where: arguments.contains) else { return }
        // A demo refresh can finish before WindowGroup has presented its window.
        var presentedWindow: NSWindow?
        for _ in 0..<20 {
            presentedWindow = NSApp.windows.first { $0.isVisible && $0.screen != nil }
            if presentedWindow != nil { break }
            await settle()
        }
        if let window = presentedWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            for _ in 0..<20 {
                await settle()
                if !window.styleMask.contains(.fullScreen) { break }
            }
        }
        guard let firstPage = pages.first, !pages.isEmpty,
              let window = presentedWindow,
              window.isVisible, !window.styleMask.contains(.fullScreen),
              let screen = window.screen else {
            finish(failures: ["A visible window in windowed mode and at least one page are required."], checks: 0, modes: 0)
            return
        }
        let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let chrome = NSSize(width: window.frame.width - window.contentLayoutRect.width,
                            height: window.frame.height - window.contentLayoutRect.height)
        let maximum = NSSize(width: visible.width - chrome.width, height: visible.height - chrome.height)
        let base = NSSize(width: 1040, height: 720)
        guard maximum.width >= base.width, maximum.height >= base.height else {
            finish(failures: ["The visible screen cannot fit the required 1040x720 content size."], checks: 0, modes: 0)
            return
        }
        var sizes = [base]
        for growth in [NSSize(width: 160, height: 80), NSSize(width: 320, height: 160)] {
            let next = NSSize(width: floor(min(maximum.width, base.width + growth.width)),
                              height: floor(min(maximum.height, base.height + growth.height)))
            if !sizes.contains(next) { sizes.append(next) }
        }
        guard sizes.count >= 2 else {
            finish(failures: ["The visible screen cannot fit a second distinct window size."], checks: 0, modes: 0)
            return
        }
        var failures = [String]()
        var checks = 0
        for (mode, size) in sizes.enumerated() {
            selectPage(firstPage)
            await settle()
            // Exercise the same NSWindow frame changes caused by ordinary window resizing
            // and moving; no full-screen transition, bitmap capture, or forced layout pass.
            // SwiftUI can use fullSizeContentView: setContentSize then includes the
            // toolbar. Request the usable contentLayoutRect size explicitly instead.
            window.setFrame(NSRect(origin: window.frame.origin,
                size: NSSize(width: size.width + chrome.width, height: size.height + chrome.height)), display: true)
            let shift = CGFloat(mode - 1) * 12
            let x = max(visible.minX, min(visible.maxX - window.frame.width,
                                       visible.midX - window.frame.width / 2 + shift))
            let y = max(visible.minY, min(visible.maxY - window.frame.height,
                                       visible.midY - window.frame.height / 2 + shift))
            window.setFrameOrigin(NSPoint(x: x, y: y))
            await settle()
            let baseline = frames(window)
            let actualSize = window.contentLayoutRect.size
            if abs(actualSize.width - size.width) > 1 || abs(actualSize.height - size.height) > 1 {
                failures.append("mode=\(mode + 1) manual resize was not accepted: requested=\(size), actual=\(actualSize)")
            }
            let missing = probeNames.filter { baseline[$0] == nil }
            if !missing.isEmpty {
                finish(failures: ["Missing visible probes: \(missing.joined(separator: ", "))."], checks: checks, modes: mode)
                return
            }
            output("WINDOW_LAYOUT_BASELINE mode=\(mode + 1) requested=\(Int(size.width))x\(Int(size.height)) \(description(baseline))")
            for (direction, order) in [("forward", pages), ("reverse", Array(pages.reversed()))] {
                for page in order {
                    selectPage(page)
                    await settle()
                    checks += 1
                    let current = frames(window)
                    let changed = frameNames.filter { name in
                        guard let expected = baseline[name], let actual = current[name] else { return true }
                        return !matches(expected, actual, tolerance: 1 / max(1, window.backingScaleFactor))
                    }
                    if !changed.isEmpty {
                        failures.append("mode=\(mode + 1) \(direction) page=\(page) changed=\(changed.joined(separator: ",")) \(description(current))")
                    }
                }
            }
        }
        finish(failures: failures, checks: checks, modes: sizes.count)
    }

    private static func settle() async { try? await Task.sleep(nanoseconds: 220_000_000) }

    private static func frames(_ window: NSWindow) -> [String: NSRect] {
        var result = ["window": window.frame, "content": window.contentLayoutRect,
                      "minSize": NSRect(origin: .zero, size: window.minSize),
                      "contentMinSize": NSRect(origin: .zero, size: window.contentMinSize)]
        var stack = window.contentView.map { [$0] } ?? []
        while let view = stack.popLast() {
            guard !view.isHiddenOrHasHiddenAncestor else { continue }
            if let probe = view as? WindowLayoutProbeView, probeNames.contains(probe.probeID) {
                result[probe.probeID] = probe.convert(probe.bounds, to: nil)
            }
            stack.append(contentsOf: view.subviews)
        }
        return result
    }

    private static func matches(_ expected: NSRect, _ actual: NSRect, tolerance: CGFloat) -> Bool {
        abs(expected.minX - actual.minX) <= tolerance && abs(expected.minY - actual.minY) <= tolerance
            && abs(expected.width - actual.width) <= tolerance && abs(expected.height - actual.height) <= tolerance
    }

    private static func description(_ frames: [String: NSRect]) -> String {
        frameNames.map { name in
            guard let frame = frames[name] else { return "\(name)=missing" }
            return "\(name)=" + String(format: "%.1f,%.1f,%.1f,%.1f", frame.minX, frame.minY, frame.width, frame.height)
        }.joined(separator: " ")
    }

    private static func output(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }

    private static func finish(failures: [String], checks: Int, modes: Int) {
        if failures.isEmpty {
            output("WINDOW_LAYOUT_PASS modes=\(modes) page_checks=\(checks) tolerance=1px")
        } else {
            output("WINDOW_LAYOUT_FAIL modes=\(modes) page_checks=\(checks) failures=\(failures.count)")
            let details = failures.prefix(12).joined(separator: "\n")
            FileHandle.standardError.write(Data(("WINDOW_LAYOUT_FAIL\n" + details + "\n").utf8))
        }
        NSApp.terminate(nil)
    }
}
