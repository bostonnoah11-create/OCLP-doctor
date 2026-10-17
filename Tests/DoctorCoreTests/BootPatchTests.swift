import Foundation
import Testing
@testable import DoctorCore

@Suite
struct BootPatchTests {
    @Test
    func testOpenCoreSeparatesBootloaderAndOCLPBuildVersions() async {
        let runner = BootPatchRunner(outputs: [
            .openCoreVersion: nvram(.openCoreVersion, "REL-104-2025-03-03%00"),
            .oclpVersion: nvram(.oclpVersion, "2.4.1"),
            .oclpSettings: nvram(.oclpSettings, " -allow_fv -allow_amfi private=SECRET")
        ])
        let section = await OpenCoreCollector(runner: runner).collect()
        #expect(section.item("openCoreVersion")?.value == "REL-104-2025-03-03")
        #expect(section.item("oclpBootVersion")?.value == "2.4.1")
        #expect(section.item("oclpSettings")?.value == "-allow_fv -allow_amfi [redacted]")
        #expect(!encoded(section).contains("SECRET"))
    }

    @Test
    func testHiddenAndUnavailableOpenCoreRemainUnknown() async {
        let hidden = await OpenCoreCollector(runner: BootPatchRunner(outputs: [
            .openCoreVersion: nvram(.openCoreVersion, "UNK-000-0000-00-00")
        ])).collect()
        #expect(hidden.item("openCoreVersion")?.status == .unknown)
        #expect(hidden.item("oclpBootVersion")?.status == .unknown)
        let unavailable = await OpenCoreCollector(runner: BootPatchRunner(outputs: [:])).collect()
        #expect(unavailable.item("openCoreVersion")?.value == nil)
        #expect(unavailable.item("openCoreVersion")?.status == .unknown)
    }

    @Test
    func testNVRAMDecodesUTF8BytesAndRejectsMalformedOrWrongKey() {
        #expect(NVRAMValue.string(nvram(.bootArgs, "caf%c3%a9%00")) == "café")
        #expect(NVRAMValue.string(nvram(.bootArgs, "%ff")) == nil)
        #expect(NVRAMValue.string(nvram(.bootArgs, "%0G")) == nil)
        #expect(NVRAMValue.string(nvram(.bootArgs, "%")) == nil)
        #expect(NVRAMValue.string(nvram(.bootArgs, "-v%00SECRET")) == nil)
        #expect(NVRAMValue.string(CommandOutput(command: .bootArgs, stdout: "boot-args-private\tSECRET")) == nil)
        #expect(NVRAMValue.string(CommandOutput(command: .bootArgs, stdout: "boot-args\t-v\nprivate\tSECRET")) == nil)
        #expect(NVRAMValue.string(nvram(.bootArgs, "")) == "")
    }

    @Test
    func testSecurityShowsObservedSettingsWithoutTreatingLoweredSIPAsFailure() async {
        let runner = BootPatchRunner(outputs: [
            .sip: CommandOutput(command: .sip, stdout: "System Integrity Protection status: disabled.\n"),
            .authenticatedRoot: CommandOutput(command: .authenticatedRoot, stdout: "Authenticated Root status: disabled."),
            .fileVault: CommandOutput(command: .fileVault, stdout: "FileVault is On."),
            .csrConfig: nvram(.csrConfig, "%03%08%00%00"),
            .bootArgs: nvram(.bootArgs, "-v keepsyms=1 debug=0x100")
        ])
        let section = await SecurityCollector(runner: runner).collect()
        #expect(section.item("sip")?.value == "Disabled")
        #expect(section.item("sip")?.status == .healthy)
        #expect(section.item("authenticatedRoot")?.value == "Disabled")
        #expect(section.item("fileVault")?.value == "On")
        #expect(section.item("csrConfig")?.value == "0x00000803")
        #expect(section.item("bootArgs")?.value == "-v keepsyms=1 debug=0x100")
    }

    @Test
    func testAuthenticatedRootAcceptsKnownStatesWithOrWithoutPeriod() async {
        for state in ["enabled", "disabled"] {
            for punctuation in ["", "."] {
                let section = await SecurityCollector(runner: BootPatchRunner(outputs: [
                    .authenticatedRoot: CommandOutput(command: .authenticatedRoot,
                        stdout: "Authenticated Root status: " + state + punctuation + "\n")
                ])).collect()
                #expect(section.item("authenticatedRoot")?.value == (state == "enabled" ? "Enabled" : "Disabled"))
            }
        }
    }

    @Test
    func testCSRPreservesLeadingSpaceByteAndRejectsUnexpectedLength() async {
        let section = await SecurityCollector(runner: BootPatchRunner(outputs: [
            .csrConfig: nvram(.csrConfig, " %00%00%00")
        ])).collect()
        #expect(section.item("csrConfig")?.value == "0x00000020")
        let invalid = await SecurityCollector(runner: BootPatchRunner(outputs: [
            .csrConfig: nvram(.csrConfig, "%03%08")
        ])).collect()
        #expect(invalid.item("csrConfig")?.value == nil)
    }

    @Test
    func testPrivateBootArgumentsAndErrorsNeverReachReportValues() async {
        let runner = BootPatchRunner(outputs: [
            .bootArgs: nvram(.bootArgs, "-v password=SECRET private-key=192.0.2.12 root=/Users/PrivateUser debug=SECRET keepsyms=1 --SECRET"),
            .sip: CommandOutput(command: .sip, stdout: "System Integrity Protection status: enabled.", stderr: "SECRET", exitCode: 1),
            .fileVault: CommandOutput(command: .fileVault, stdout: "PRIVATE STATE SECRET"),
            .authenticatedRoot: CommandOutput(command: .authenticatedRoot, stderr: "/Users/PrivateUser", exitCode: nil, termination: .timedOut)
        ])
        let section = await SecurityCollector(runner: runner).collect()
        let report = encoded(section)
        for privateValue in ["SECRET", "PrivateUser", "192.0.2.12", "private-key", "password"] {
            #expect(!report.contains(privateValue))
        }
        #expect(section.item("bootArgs")?.value == "-v [redacted] [redacted] [redacted] debug=[redacted] keepsyms=1 [redacted]")
        #expect(section.item("sip")?.value == nil)
        #expect(section.item("fileVault")?.value == nil)
        #expect(section.item("authenticatedRoot")?.status == .unknown)
    }

    @Test
    func testCustomSIPIsNotFlattenedToEnabledOrDisabled() async {
        let section = await SecurityCollector(runner: BootPatchRunner(outputs: [
            .sip: CommandOutput(command: .sip, stdout: "System Integrity Protection status: unknown (Custom Configuration).\n\nConfiguration:\n    Filesystem Protections: disabled\n    Kext Signing: enabled\nPrivateKey: SECRET\nDebugging Restrictions: SECRET")
        ])).collect()
        #expect(section.item("sip")?.value == "Custom Configuration")
        #expect(section.item("sip")?.status == .unknown)
        #expect(section.item("sipConfiguration")?.value == "Kext Signing: Enabled · Filesystem Protections: Disabled")
        #expect(!encoded(section).contains("SECRET"))
    }

    @Test
    func testRootPatchMetadataIsEvidenceNotProofOfValidPatches() async throws {
        let metadata: [String: Any] = [
            "OpenCore Legacy Patcher": "v2.4.1", "Time Patched": "October 17, 2026 @ 09:15:23",
            "OS Version": "24.5 (24F74)",
            "Kernel Debug Kit Used": "/Users/PrivateUser/SECRET.kdk", "Commit URL": "https://private.example/SECRET",
            "Intel Ivy Bridge": ["Execute": ["SECRET COMMAND": true]],
            "Intel Haswell": ["Execute": ["SECRET COMMAND": true]],
            "AMD Legacy GCN": ["Execute": ["SECRET COMMAND": true]],
            "Legacy Wireless": ["Overwrite System Volume": ["/private/SECRET": "SECRET"]],
            "SECRET PRIVATE KEY": ["Execute": ["SECRET": true]]
        ]
        let reader = BootPatchFileReader(files: [PatchCollector.metadataURL.path: .data(try plist(metadata))])
        let section = await PatchCollector(reader: reader).collect()
        #expect(section.item("rootPatchState")?.status == .unknown)
        #expect(section.item("rootPatchVersion")?.value == "2.4.1")
        #expect(section.item("rootPatchOS")?.value == "24.5 (24F74)")
        #expect(section.item("rootPatchDate")?.value == "October 17, 2026 @ 09:15:23")
        #expect(section.item("patchSets")?.value?.contains("Intel Ivy Bridge") == true)
        #expect(section.item("patchSets")?.value?.contains("Intel Haswell") == true)
        #expect(section.item("patchSets")?.value?.contains("AMD Legacy GCN") == true)
        #expect(!encoded(section).contains("SECRET"))
        #expect(!encoded(section).contains("PrivateUser"))
    }

    @Test
    func testMissingUnreadableOversizedAndMalformedPatchMetadataStayUnknown() async throws {
        let outcomes: [FileReadOutcome] = [.missing, .unreadable, .tooLarge, .data(Data("invalid".utf8)),
            .data(try plist(["Time Patched": "SECRET"])), .data(Data(repeating: 0, count: 1_048_577))]
        for outcome in outcomes {
            let section = await PatchCollector(reader: BootPatchFileReader(files: [PatchCollector.metadataURL.path: outcome])).collect()
            #expect(section.item("rootPatchState")?.status == .unknown)
            #expect(section.item("rootPatchVersion") == nil)
            #expect(!encoded(section).contains("SECRET"))
        }
    }

    @Test
    func testMetadataStringFieldsRejectPrivateOrUnexpectedFormats() async throws {
        let section = await PatchCollector(reader: BootPatchFileReader(files: [
            PatchCollector.metadataURL.path: .data(try plist([
                "OpenCore Legacy Patcher": "v2.4.1", "Time Patched": "/Users/PrivateUser/SECRET", "OS Version": "SECRET"
            ]))
        ])).collect()
        #expect(section.item("rootPatchDate")?.value == nil)
        #expect(section.item("rootPatchOS")?.value == nil)
        #expect(!encoded(section).contains("SECRET"))
    }

    @Test
    func testInstalledAppValidatesBundleIDAndDeduplicatesResolvedPaths() async throws {
        let canonical = URL(fileURLWithPath: "/Users/PrivateUser/SECRET.app")
        let reader = BootPatchFileReader(files: [
            canonical.appendingPathComponent("Contents/Info.plist").path: .data(try plist([
                "CFBundleIdentifier": "com.dortania.opencore-legacy-patcher", "CFBundleShortVersionString": "2.5.1"
            ]))
        ], aliases: Dictionary(uniqueKeysWithValues: PatchCollector.appURLs.map { ($0.path, canonical) }))
        let section = await PatchCollector(reader: reader).collect()
        #expect(section.item("installedOCLP")?.value == "2.5.1")
        #expect(section.item("installedOCLP")?.evidence.count == 1)
        #expect(!encoded(section).contains("PrivateUser"))
        #expect(!encoded(section).contains("SECRET"))
        let fake = BootPatchFileReader(files: [
            PatchCollector.appURLs[0].appendingPathComponent("Contents/Info.plist").path: .data(try plist([
                "CFBundleIdentifier": "com.private.SECRET", "CFBundleShortVersionString": "2.5.1"
            ]))
        ])
        let fakeSection = await PatchCollector(reader: fake).collect()
        #expect(fakeSection.item("installedOCLP")?.value == nil)
        #expect(fakeSection.item("installedOCLPPresence")?.status == .unknown)
    }

    @Test
    func testAppPresenceIsKnownEvenWhenVersionIsNot() async throws {
        let reader = BootPatchFileReader(files: [
            PatchCollector.appURLs[0].appendingPathComponent("Contents/Info.plist").path: .data(try plist([
                "CFBundleIdentifier": "com.dortania.opencore-legacy-patcher", "CFBundleShortVersionString": "SECRET"
            ]))
        ])
        let section = await PatchCollector(reader: reader).collect()
        #expect(section.item("installedOCLPPresence")?.status == .healthy)
        #expect(section.item("installedOCLP")?.value == nil)
        #expect(!encoded(section).contains("SECRET"))
    }

    @Test
    func testLocalFileReaderBoundsReadsAndDistinguishesMissing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OCLPDoctorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("fixture.plist")
        let reader = LocalFileReader()
        #expect(reader.read(file, maxBytes: 4) == .missing)
        #expect(reader.read(directory, maxBytes: 4) == .unreadable)
        try Data([0, 1, 2, 3]).write(to: file)
        #expect(reader.read(file, maxBytes: 4) == .data(Data([0, 1, 2, 3])))
        #expect(reader.read(file, maxBytes: 3) == .tooLarge)
        try Data(repeating: 0, count: 1_048_577).write(to: file)
        #expect(reader.read(file, maxBytes: Int.max) == .tooLarge)
    }

    private func nvram(_ command: DiagnosticCommand, _ value: String) -> CommandOutput {
        CommandOutput(command: command, stdout: command.arguments.last! + "\t" + value + "\n")
    }

    private func plist(_ dictionary: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
    }

    private func encoded(_ section: DiagnosticSection) -> String {
        String(data: try! JSONEncoder().encode(section), encoding: .utf8)!
    }
}

private struct BootPatchRunner: CommandExecuting {
    let outputs: [DiagnosticCommand: CommandOutput]
    func run(_ command: DiagnosticCommand) async -> CommandOutput {
        outputs[command] ?? CommandOutput(command: command, exitCode: 1)
    }
}

private struct BootPatchFileReader: FileReading {
    let files: [String: FileReadOutcome]
    var aliases: [String: URL] = [:]
    func read(_ url: URL, maxBytes: Int) -> FileReadOutcome { files[url.path] ?? .missing }
    func canonicalURL(for url: URL) -> URL { aliases[url.path] ?? url }
}
