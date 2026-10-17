import Foundation
import Testing
@testable import DoctorCore

@Suite
struct CommandRunnerTests {
    @Test func testClosedCommandsDoNotContainMutationOptions() {
        for command in DiagnosticCommand.allCases {
            #expect(command.executable.hasPrefix("/usr/"))
            #expect(!(command.arguments.contains("enable")))
            #expect(!(command.arguments.contains("disable")))
            #expect(!(command.arguments.contains("-c")))
            #expect(!(command.arguments.contains("-d")))
            if command.executable == "/usr/sbin/nvram" {
                #expect(command.arguments.count == 1)
                #expect(!(command.arguments.contains(where: { $0.contains("=") })))
            }
        }
        #expect(DiagnosticCommand.powerHistory.arguments == ["-g", "log"])
        #expect(DiagnosticCommand.sleepWakeLog.arguments.first == "show")
        #expect(DiagnosticCommand.sleepWakeLog.arguments.contains("--predicate"))
    }

    @Test func testStdoutStderrAndExitCode() async {
        let output = await CommandRunner().execute(.cpu, executable: "/bin/sh",
            arguments: ["-c", "printf observed; printf problem >&2; exit 7"], timeout: 2)
        #expect(output.stdout == "observed")
        #expect(output.stderr == "problem")
        #expect(output.exitCode == 7)
        #expect(output.termination == .completed)
        #expect(!(output.succeeded))
        #expect(output.text == nil)
    }

    @Test func testMissingExecutableDoesNotThrow() async {
        let output = await CommandRunner().execute(.cpu, executable: "/does-not-exist/oclp-doctor-test",
            arguments: [], timeout: 1)
        #expect(output.termination == .launchFailed)
        #expect(output.exitCode == nil)
    }

    @Test func testTimeoutIsBounded() async {
        let start = ProcessInfo.processInfo.systemUptime
        let output = await CommandRunner().execute(.cpu, executable: "/bin/sleep", arguments: ["10"], timeout: 0.1)
        #expect(output.termination == .timedOut)
        #expect(ProcessInfo.processInfo.systemUptime - start < 2)
    }

    @Test func testUnboundedOutputIsCappedWithoutPipeDeadlock() async {
        let output = await CommandRunner().execute(.cpu, executable: "/usr/bin/yes", arguments: [],
            timeout: 2, outputLimit: 16_384)
        #expect(output.termination == .outputLimit)
        #expect(output.outputWasTruncated)
        #expect(output.stdout.utf8.count + output.stderr.utf8.count <= 16_384)
    }

    @Test func testCancellationStopsLaunchedProcess() async throws {
        let task = Task {
            await CommandRunner().execute(.cpu, executable: "/bin/sleep", arguments: ["10"], timeout: 20)
        }
        try await Task.sleep(nanoseconds: 60_000_000)
        task.cancel()
        let output = await task.value
        #expect(output.termination == .cancelled)
    }

    @Test func testLargeBothPipesAreDrained() async {
        let output = await CommandRunner().execute(.cpu, executable: "/bin/sh",
            arguments: ["-c", "i=0; while [ $i -lt 4000 ]; do printf '1234567890abcdefghij'; printf 'abcdefghij1234567890' >&2; i=$((i+1)); done"],
            timeout: 5)
        #expect(output.succeeded)
        #expect(output.stdout.utf8.count == 80_000)
        #expect(output.stderr.utf8.count == 80_000)
    }

    @Test func testTailRetentionKeepsMostRecentOutput() async {
        let output = await CommandRunner().execute(.powerHistory, executable: "/bin/sh",
            arguments: ["-c", "i=0; while [ $i -lt 4000 ]; do printf 'old-record-1234567890\\n'; i=$((i+1)); done; printf 'latest-wake-record\\n'"],
            timeout: 5, outputLimit: 16_384, retainTail: true)
        #expect(output.succeeded)
        #expect(output.outputWasTruncated)
        #expect(output.stdout.utf8.count <= 16_384)
        #expect(output.stdout.hasSuffix("latest-wake-record\n"))
    }

    @Test func testTailModeStillBoundsEndlessScans() async {
        let start = ProcessInfo.processInfo.systemUptime
        let output = await CommandRunner().execute(.sleepWakeLog, executable: "/usr/bin/yes",
            arguments: [], timeout: 2, outputLimit: 4096, retainTail: true, scanLimit: 65_536)
        #expect(output.termination == .outputLimit)
        #expect(output.outputWasTruncated)
        #expect(output.stdout.utf8.count <= 4096)
        #expect(ProcessInfo.processInfo.systemUptime - start < 2)
    }

    @Test func focusedLifecycleCommandRequiresValidatedDatesAndHCIUsesCompactFullBuffer() async throws {
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        let end = start.addingTimeInterval(420)
        let hci = try #require(DiagnosticCommand.wakeBluetoothArguments(since: start, until: end))
        #expect(hci.contains("compact"))
        #expect(DiagnosticCommand.wakeBluetoothLog.outputLimit == 64 * 1_048_576)
        #expect(!DiagnosticCommand.wakeBluetoothLog.keepsOutputTail)
        let lifecycle = try #require(DiagnosticCommand.wakeBluetoothLifecycleArguments(since: start, until: end))
        #expect(lifecycle.contains("ndjson"))
        #expect(lifecycle.last?.contains("launchd") == true)
        #expect(lifecycle.last?.contains("com.apple.bluetoothd") == true)
        #expect(lifecycle.last?.contains("CONTAINS[c] \"daemon\"") == false)
        #expect(DiagnosticCommand.wakeBluetoothLifecycleArguments(since: start, until: end.addingTimeInterval(1)) == nil)
        #expect(DiagnosticCommand.wakeIncidentArguments(since: start, until: end.addingTimeInterval(-0.25)) == nil)
        #expect(DiagnosticCommand.wakeBluetoothArguments(since: start.addingTimeInterval(0.25), until: end) == nil)
        #expect(await CommandRunner().run(.wakeBluetoothLifecycleLog).termination == .launchFailed)
        #expect(await CommandRunner().runWakeBluetoothLifecycleLog(since: end, until: start).termination == .launchFailed)
        let evidence = CommandOutput(command: .wakeBluetoothLifecycleLog, windowStart: start, windowEnd: end).evidence
        #expect(evidence.source.contains("--start") && evidence.source.contains("com.apple.bluetoothd"))
    }
}
