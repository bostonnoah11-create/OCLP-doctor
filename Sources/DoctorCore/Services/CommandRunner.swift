import Foundation
import Darwin

/// Runs bounded read-only subprocesses off the main thread, without invoking a shell.
public struct CommandRunner: CommandExecuting {
    public init() {}
    public func run(_ command: DiagnosticCommand) async -> CommandOutput {
        guard command != .wakeIncidentLog && command != .wakeBluetoothLog && command != .wakeBluetoothLifecycleLog else { return CommandOutput(command: command, exitCode: nil, termination: .launchFailed) }
        return await execute(command, executable: command.executable, arguments: command.arguments,
                      timeout: command.timeout, outputLimit: command.outputLimit,
                      retainTail: command.keepsOutputTail)
    }

    public func runWakeIncidentLog(since: Date, until: Date) async -> CommandOutput {
        guard let arguments = DiagnosticCommand.wakeIncidentArguments(since: since, until: until) else {
            return CommandOutput(command: .wakeIncidentLog, exitCode: nil, termination: .launchFailed)
        }
        let output = await execute(.wakeIncidentLog, executable: DiagnosticCommand.wakeIncidentLog.executable,
            arguments: arguments, timeout: DiagnosticCommand.wakeIncidentLog.timeout,
            outputLimit: DiagnosticCommand.wakeIncidentLog.outputLimit, retainTail: true)
        return CommandOutput(command: output.command, stdout: output.stdout, stderr: output.stderr,
            exitCode: output.exitCode, termination: output.termination, outputWasTruncated: output.outputWasTruncated,
            windowStart: since, windowEnd: until)
    }

    public func runWakeBluetoothLog(since: Date, until: Date) async -> CommandOutput {
        guard let arguments = DiagnosticCommand.wakeBluetoothArguments(since: since, until: until) else {
            return CommandOutput(command: .wakeBluetoothLog, exitCode: nil, termination: .launchFailed)
        }
        let output = await execute(.wakeBluetoothLog, executable: DiagnosticCommand.wakeBluetoothLog.executable,
            arguments: arguments, timeout: DiagnosticCommand.wakeBluetoothLog.timeout,
            outputLimit: DiagnosticCommand.wakeBluetoothLog.outputLimit, retainTail: false)
        return CommandOutput(command: output.command, stdout: output.stdout, stderr: output.stderr,
            exitCode: output.exitCode, termination: output.termination, outputWasTruncated: output.outputWasTruncated,
            windowStart: since, windowEnd: until)
    }

    public func runWakeBluetoothLifecycleLog(since: Date, until: Date) async -> CommandOutput {
        guard let arguments = DiagnosticCommand.wakeBluetoothLifecycleArguments(since: since, until: until) else {
            return CommandOutput(command: .wakeBluetoothLifecycleLog, exitCode: nil, termination: .launchFailed)
        }
        let output = await execute(.wakeBluetoothLifecycleLog, executable: DiagnosticCommand.wakeBluetoothLifecycleLog.executable,
            arguments: arguments, timeout: DiagnosticCommand.wakeBluetoothLifecycleLog.timeout,
            outputLimit: DiagnosticCommand.wakeBluetoothLifecycleLog.outputLimit, retainTail: false)
        return CommandOutput(command: output.command, stdout: output.stdout, stderr: output.stderr,
            exitCode: output.exitCode, termination: output.termination, outputWasTruncated: output.outputWasTruncated,
            windowStart: since, windowEnd: until)
    }

    // Internal seam for testing process failure, deadline, and pipe behavior.
    func execute(_ command: DiagnosticCommand, executable: String, arguments: [String],
                 timeout: TimeInterval, outputLimit: Int = 1_048_576, retainTail: Bool = false,
                 scanLimit: Int = 32 * 1_048_576) async -> CommandOutput {
        let cancellation = CancellationFlag()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: Self.perform(command, executable: executable,
                        arguments: arguments, timeout: timeout, outputLimit: outputLimit,
                        retainTail: retainTail, scanLimit: scanLimit,
                        cancellation: cancellation))
                }
            }
        }, onCancel: { cancellation.cancel() })
    }

    private static func perform(_ command: DiagnosticCommand, executable: String,
                                arguments: [String], timeout: TimeInterval, outputLimit: Int,
                                retainTail: Bool, scanLimit: Int,
                                cancellation: CancellationFlag) -> CommandOutput {
        if cancellation.isCancelled {
            return CommandOutput(command: command, exitCode: nil, termination: .cancelled)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Fixed locale makes text parsers deterministic. No inherited DYLD or shell environment.
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        defer {
            try? out.fileHandleForReading.close()
            try? err.fileHandleForReading.close()
            try? out.fileHandleForWriting.close()
            try? err.fileHandleForWriting.close()
        }
        for fd in [out.fileHandleForReading.fileDescriptor, err.fileHandleForReading.fileDescriptor] {
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else {
                return CommandOutput(command: command, exitCode: nil, termination: .launchFailed)
            }
        }
        do { try process.run() } catch {
            return CommandOutput(command: command, exitCode: nil, termination: .launchFailed)
        }
        try? out.fileHandleForWriting.close()
        try? err.fileHandleForWriting.close()
        var stdout = Data(), stderr = Data()
        var termination: CommandTermination = .completed
        let deadline = ProcessInfo.processInfo.systemUptime + max(0.01, timeout)
        var exceeded = false
        var truncated = false
        var bytesRead = 0

        func drain(_ handle: FileHandle, into data: inout Data) {
            var buffer = [UInt8](repeating: 0, count: 8192)
            // Limit each pump so an always-writing process cannot starve the deadline check.
            for _ in 0..<32 {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count) }
                if count > 0 {
                    if retainTail {
                        let remaining = max(0, scanLimit - bytesRead)
                        bytesRead += count
                        data.append(contentsOf: buffer.prefix(min(count, remaining)))
                        if count > remaining { exceeded = true; truncated = true; return }
                        continue
                    }
                    let remaining = max(0, outputLimit - stdout.count - stderr.count - data.count)
                    data.append(contentsOf: buffer.prefix(min(count, remaining)))
                    if count > remaining { exceeded = true; truncated = true; return }
                } else if count == -1 && errno == EINTR {
                    continue
                } else { return }
            }
        }

        func pump() {
            var chunk = Data()
            drain(out.fileHandleForReading, into: &chunk)
            stdout.append(chunk)
            if retainTail && stdout.count > outputLimit {
                stdout.removeFirst(stdout.count - outputLimit)
                truncated = true
            }
            chunk = Data()
            drain(err.fileHandleForReading, into: &chunk)
            stderr.append(chunk)
            if retainTail && stderr.count > 65_536 {
                stderr.removeFirst(stderr.count - 65_536)
                truncated = true
            }
        }

        while true {
            pump()
            if exceeded { termination = .outputLimit; break }
            if cancellation.isCancelled { termination = .cancelled; break }
            if !process.isRunning { break }
            if ProcessInfo.processInfo.systemUptime >= deadline { termination = .timedOut; break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            process.terminate()
            let grace = ProcessInfo.processInfo.systemUptime + 0.25
            while process.isRunning && ProcessInfo.processInfo.systemUptime < grace {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning {
                // Kill only the subprocess we launched; never system services or arbitrary PIDs.
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                let killDeadline = ProcessInfo.processInfo.systemUptime + 0.5
                while process.isRunning && ProcessInfo.processInfo.systemUptime < killDeadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
        }
        if termination == .completed {
            pump()
            if exceeded { termination = .outputLimit }
        }
        return CommandOutput(command: command, stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self),
            exitCode: process.isRunning ? nil : process.terminationStatus, termination: termination,
            outputWasTruncated: truncated)
    }
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}
