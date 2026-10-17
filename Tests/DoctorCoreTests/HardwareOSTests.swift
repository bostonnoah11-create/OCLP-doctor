import Foundation
import Testing
@testable import DoctorCore

@Suite
struct HardwareOSTests {
    @Test
    func metalGPUFamilySupportReportsMetal2WithoutClaimingWorkingAcceleration() async throws {
        let runner = HardwareOSFixtureRunner(outputs: [
            .displays: .init(command: .displays, stdout: #"{"SPDisplaysDataType":[{"sppci_model":"AMD FirePro D500","spdisplays_mtlgpufamilysupport":"spdisplays_metal2","spdisplays_metal":"spdisplays_supported"},{"sppci_model":"AMD FirePro D500","spdisplays_mtlgpufamilysupport":"spdisplays_metal2"}]}"#)
        ])
        let hardware = await HardwareCollector(runner: runner).collect()
        try #require(hardware.gpus.count == 2)
        for gpu in hardware.gpus {
            #expect(gpu.metal.value == "Metal 2 (spdisplays_metal2)")
            #expect(gpu.metal.message.contains("does not verify graphics acceleration"))
            #expect(gpu.metal.evidence.contains { $0.detail.contains("spdisplays_mtlgpufamilysupport") })
        }
    }

    @Test
    func malformedMetalFamilyUsesOtherObservedMetalFieldOrUnknown() async throws {
        let runner = HardwareOSFixtureRunner(outputs: [
            .displays: .init(command: .displays, stdout: #"{"SPDisplaysDataType":[{"spdisplays_mtlgpufamilysupport":true,"spdisplays_metal":"spdisplays_supported"},{"spdisplays_mtlgpufamilysupport":"Unknown"}]}"#)
        ])
        let hardware = await HardwareCollector(runner: runner).collect()
        try #require(hardware.gpus.count == 2)
        #expect(hardware.gpus[0].metal.value == "Supported (spdisplays_supported)")
        #expect(hardware.gpus[1].metal.status == .unknown)
    }

    @Test
    func preservedFirmwareModelDetectsExposedModelDifferenceWithoutTreatingItAsAnError() async throws {
        var outputs = HardwareOSFixtureRunner.macPro.outputs
        outputs[.hardware] = .init(command: .hardware, stdout: #"{"SPHardwareDataType":[{"machine_name":"Mac Pro","machine_model":"MacPro7,1"}]}"#)
        outputs[.originalModelIdentifier] = originalModelOutput("MacPro6,1%00")
        let hardware = await HardwareCollector(runner: HardwareOSFixtureRunner(outputs: outputs)).collect()
        let original = try #require(hardware.section.item("originalModelIdentifier"))
        let comparison = try #require(hardware.section.item("modelSpoofing"))
        #expect(original.label == "Preserved Firmware Model")
        #expect(original.value == "MacPro6,1")
        #expect(original.status == .healthy)
        #expect(comparison.value == "Detected")
        #expect(comparison.status == .healthy)
        #expect(comparison.message.contains("MacPro7,1"))
        #expect(comparison.message.contains("MacPro6,1"))
        #expect(comparison.message.contains("not classified as an error"))
        #expect(hardware.overviewModelTitle == "Mac Pro 7,1 (spoofed)")
        #expect(hardware.overviewModelNote.contains("Preserved firmware model: Mac Pro 6,1"))
        #expect(original.evidence.contains {
            $0.source == "/usr/sbin/nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:oem-product"
        })
        #expect(comparison.evidence.contains { $0.source == DiagnosticCommand.hardware.source })
        #expect(comparison.evidence.contains { $0.source == DiagnosticCommand.originalModelIdentifier.source })
    }

    @Test
    func matchingPreservedAndExposedModelsDoNotInferSpoofingFromSysctlDisagreement() async {
        var outputs = HardwareOSFixtureRunner.macPro.outputs
        outputs[.originalModelIdentifier] = originalModelOutput("MacPro6,1")
        outputs[.modelIdentifier] = .init(command: .modelIdentifier, stdout: "MacBookPro11,3")
        let hardware = await HardwareCollector(runner: HardwareOSFixtureRunner(outputs: outputs)).collect()
        #expect(hardware.section.item("modelIdentifier")?.value == "MacPro6,1")
        #expect(hardware.section.item("modelSpoofing")?.value == "Not detected")
        #expect(hardware.section.item("modelSpoofing")?.status == .healthy)
        #expect(hardware.overviewModelTitle == "Mac Pro 6,1")

        var notebookOutputs = HardwareOSFixtureRunner.macBookPro.outputs
        notebookOutputs[.originalModelIdentifier] = originalModelOutput("MacBookPro11,3")
        let notebook = await HardwareCollector(runner: HardwareOSFixtureRunner(outputs: notebookOutputs)).collect()
        #expect(notebook.section.item("modelSpoofing")?.value == "Not detected")
        #expect(notebook.overviewModelTitle == "MacBook Pro 11,3")
    }

    @Test
    func missingOriginalOrExposedIdentityLeavesComparisonUnknown() async {
        var outputs = HardwareOSFixtureRunner.macPro.outputs
        outputs[.modelIdentifier] = .init(command: .modelIdentifier, stdout: "MacBookPro11,3")
        outputs[.openCoreVersion] = .init(command: .openCoreVersion,
            stdout: "4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version\tREL-106-2025-11-03")
        let missingOriginal = await HardwareCollector(runner: HardwareOSFixtureRunner(outputs: outputs)).collect()
        #expect(missingOriginal.section.item("originalModelIdentifier")?.status == .unknown)
        #expect(missingOriginal.section.item("modelSpoofing")?.value == nil)
        #expect(missingOriginal.section.item("modelSpoofing")?.status == .unknown)
        #expect(missingOriginal.overviewModelTitle == "Mac Pro 6,1")
        #expect(!missingOriginal.overviewModelTitle.contains("(spoofed)"))
        #expect(missingOriginal.overviewModelNote.contains("unknown"))

        let missingExposed = await HardwareCollector(runner: HardwareOSFixtureRunner(outputs: [
            .originalModelIdentifier: originalModelOutput("MacPro6,1")
        ])).collect()
        #expect(missingExposed.section.item("originalModelIdentifier")?.value == "MacPro6,1")
        #expect(missingExposed.section.item("modelIdentifier")?.status == .unknown)
        #expect(missingExposed.section.item("modelSpoofing")?.value == nil)
        #expect(missingExposed.section.item("modelSpoofing")?.status == .unknown)
    }

    @Test
    func invalidPrivateAndFailedOriginalValuesAreNotExportedOrCompared() async throws {
        let invalid = [
            originalModelOutput("PRIVATE-ORIGINAL"),
            originalModelOutput("/Users/PRIVATE-ORIGINAL/model"),
            originalModelOutput("MacPro6,1 PRIVATE-ORIGINAL"),
            originalModelOutput("MacPro6,1%00PRIVATE-ORIGINAL"),
            originalModelOutput("MacPro6,1", exitCode: 1),
            CommandOutput(command: .originalModelIdentifier,
                stdout: "unrelated-key\tMacPro6,1", stderr: "PRIVATE-STDERR")
        ]
        for output in invalid {
            var outputs = HardwareOSFixtureRunner.macPro.outputs
            outputs[.originalModelIdentifier] = output
            let hardware = await HardwareCollector(runner: HardwareOSFixtureRunner(outputs: outputs)).collect()
            #expect(hardware.section.item("originalModelIdentifier")?.value == nil)
            #expect(hardware.section.item("originalModelIdentifier")?.status == .unknown)
            #expect(hardware.section.item("modelSpoofing")?.value == nil)
            #expect(hardware.section.item("modelSpoofing")?.status == .unknown)
            #expect(!hardware.overviewModelTitle.contains("(spoofed)"))
            let encoded = String(decoding: try JSONEncoder().encode(hardware), as: UTF8.self)
            #expect(!encoded.contains("PRIVATE-ORIGINAL"))
            #expect(!encoded.contains("PRIVATE-STDERR"))
        }
    }

    @Test
    func malformedReportedIdentifiersAreRejectedBeforeComparisonOrFallback() async throws {
        let runner = HardwareOSFixtureRunner(outputs: [
            .hardware: .init(command: .hardware, stdout: #"{"SPHardwareDataType":[{"machine_model":"PRIVATE-REPORTED"}]}"#),
            .modelIdentifier: .init(command: .modelIdentifier, stdout: "MacPro6,1 PRIVATE-SYSCTL"),
            .originalModelIdentifier: originalModelOutput("MacPro6,1")
        ])
        let hardware = await HardwareCollector(runner: runner).collect()
        #expect(hardware.section.item("modelIdentifier")?.value == nil)
        #expect(hardware.section.item("modelSpoofing")?.status == .unknown)
        let encoded = String(decoding: try JSONEncoder().encode(hardware), as: UTF8.self)
        #expect(!encoded.contains("PRIVATE-REPORTED"))
        #expect(!encoded.contains("PRIVATE-SYSCTL"))
    }

    @Test
    func validatedSysctlFallbackCanBeComparedWithPreservedFirmwareModel() async throws {
        let runner = HardwareOSFixtureRunner(outputs: [
            .hardware: .init(command: .hardware, stdout: #"{"SPHardwareDataType":[{"machine_model":"invalid"}]}"#),
            .modelIdentifier: .init(command: .modelIdentifier, stdout: "MacBookPro11,3\n"),
            .originalModelIdentifier: originalModelOutput("MacPro6,1")
        ])
        let hardware = await HardwareCollector(runner: runner).collect()
        #expect(hardware.section.item("modelIdentifier")?.value == "MacBookPro11,3")
        let comparison = try #require(hardware.section.item("modelSpoofing"))
        #expect(comparison.value == "Detected")
        #expect(comparison.status == .healthy)
        #expect(comparison.evidence.contains { $0.source == "/usr/sbin/sysctl -n hw.model" })
        #expect(hardware.section.item("modelName")?.status == .unknown)
    }

    private func originalModelOutput(_ payload: String, exitCode: Int32 = 0) -> CommandOutput {
        CommandOutput(command: .originalModelIdentifier,
            stdout: "4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:oem-product\t" + payload,
            exitCode: exitCode)
    }

    @Test
    func testModelIdentifierFallsBackToSysctlWithoutInferringMarketingName() async throws {
        for hardwareJSON in [
            #"{"SPHardwareDataType":[{"machine_name":"Unknown","machine_model":"Unknown"}]}"#,
            #"{"SPHardwareDataType":[{}]}"#,
            "malformed JSON"
        ] {
            let runner = HardwareOSFixtureRunner(outputs: [
                .hardware: .init(command: .hardware, stdout: hardwareJSON),
                .modelIdentifier: .init(command: .modelIdentifier, stdout: "MacPro6,1\n")
            ])
            let hardware = await HardwareCollector(runner: runner).collect()
            let identifier = try #require(hardware.section.item("modelIdentifier"))
            #expect(identifier.value == "MacPro6,1")
            #expect(identifier.status == .healthy)
            #expect(identifier.message.contains("spoofing"))
            #expect(identifier.evidence.contains {
                $0.source == "/usr/sbin/sysctl -n hw.model" && $0.detail == "field=hw.model"
            })
            #expect(identifier.evidence.contains { $0.source == DiagnosticCommand.hardware.source })
            #expect(hardware.section.item("modelName")?.status == .unknown)
        }
    }

    @Test
    func testModelIdentifierPrefersProfilerAndIgnoresFailedFallbackOutput() async throws {
        var outputs = HardwareOSFixtureRunner.macPro.outputs
        outputs[.modelIdentifier] = .init(command: .modelIdentifier, stdout: "MacBookPro11,3")
        let hardware = await HardwareCollector(runner: HardwareOSFixtureRunner(outputs: outputs)).collect()
        let identifier = try #require(hardware.section.item("modelIdentifier"))
        #expect(identifier.value == "MacPro6,1")
        #expect(!(identifier.evidence.contains {
            $0.source == DiagnosticCommand.modelIdentifier.source
        }))

        outputs[.hardware] = .init(command: .hardware, exitCode: 1)
        outputs[.modelIdentifier] = .init(command: .modelIdentifier, stdout: "MacPro6,1", exitCode: 1)
        let failed = await HardwareCollector(runner: HardwareOSFixtureRunner(outputs: outputs)).collect()
        #expect(failed.section.item("modelIdentifier")?.value == nil)
        #expect(failed.section.item("modelIdentifier")?.status == .unknown)
    }

    @Test
    func testMacProKeepsBothIdenticallyNamedGPUs() async throws {
        let hardware = await HardwareCollector(runner: HardwareOSFixtureRunner.macPro).collect()
        #expect(hardware.section.id == "hardware")
        let identifier = try #require(hardware.section.item("modelIdentifier"))
        #expect(identifier.value == "MacPro6,1")
        #expect(identifier.message.contains("spoofing"))
        #expect(hardware.section.item("physicalCores")?.value == "12")
        #expect(hardware.section.item("logicalCores")?.value == "24")
        #expect(hardware.section.item("memory")?.value == "64 GiB (68719476736 bytes)")
        #expect(hardware.section.item("gpuCount")?.value == "2")
        try #require(hardware.gpus.count == 2)
        #expect(hardware.gpus.map(\.id) == ["gpu-0", "gpu-1"])
        #expect(hardware.gpus.map(\.name.value) == ["AMD FirePro D500", "AMD FirePro D500"])
        #expect(hardware.gpus.map(\.vram.value) == ["3 GB", "3 GB"])
        #expect(hardware.gpus.allSatisfy { $0.metal.value?.contains("spdisplays_supported") == true })
        #expect(hardware.gpus[0].name.id != hardware.gpus[1].name.id)
        let allItems = hardware.section.items + hardware.gpus.flatMap { $0.section.items }
        #expect(allItems.allSatisfy { !$0.evidence.isEmpty })
        let encoded = String(decoding: try JSONEncoder().encode(hardware), as: UTF8.self)
        #expect(!(encoded.contains("PRIVATE-SERIAL")))
        #expect(!(encoded.contains("PRIVATE-UUID")))
    }

    @Test
    func testMacBookProPreservesIntegratedAndDiscreteGPUs() async throws {
        let runner = HardwareOSFixtureRunner.macBookPro
        let hardware = await HardwareCollector(runner: runner).collect()
        #expect(hardware.section.item("modelIdentifier")?.value == "MacBookPro11,3")
        try #require(hardware.gpus.count == 2)
        #expect(hardware.gpus.map(\.name.value) == ["Intel Iris Pro", "NVIDIA GeForce GT 750M"])
        #expect(hardware.gpus[0].vram.value == "1536 MB")
        #expect(hardware.gpus[0].vram.evidence.contains { $0.detail.contains("spdisplays_vram_shared") })
        #expect(hardware.gpus[1].vram.value == "2 GB")
        // The second fixture intentionally omits Metal. Model identity must not fill that gap.
        #expect(hardware.gpus[1].metal.status == .unknown)
        #expect(hardware.gpus[1].metal.value == nil)
    }

    @Test
    func testMissingOrMalformedHardwareNeverInfersSpecsFromModel() async throws {
        let runner = HardwareOSFixtureRunner(outputs: [
            .hardware: .init(command: .hardware, stdout: #"{"SPHardwareDataType":[{"machine_name":"Unknown","machine_model":"MacPro6,1","cpu_type":"Intel Xeon","physical_memory":"64 GB"}]}"#),
            .displays: .init(command: .displays, stdout: #"{"SPDisplaysDataType":[{"sppci_model":"AMD FirePro D500","spdisplays_vram":3,"spdisplays_metal":true}]}"#),
            .physicalCores: .init(command: .physicalCores, stdout: "-1"),
            .logicalCores: .init(command: .logicalCores, stdout: "24 cores"),
            .memory: .init(command: .memory, stdout: "18446744073709551616")
        ])
        let hardware = await HardwareCollector(runner: runner).collect()
        for id in ["modelName", "cpu", "physicalCores", "logicalCores", "memory"] {
            #expect(hardware.section.item(id)?.status == .unknown, "field: \(id)")
        }
        try #require(hardware.gpus.count == 1)
        #expect(hardware.gpus[0].vram.status == .unknown)
        #expect(hardware.gpus[0].metal.status == .unknown)
    }

    @Test
    func testInvalidJSONAndWrongTopLevelTypesReturnUnknown() async throws {
        for json in ["not json", "[]", #"{"SPDisplaysDataType":{}}"#, #"{"SPDisplaysDataType":[null]}"#] {
            let runner = HardwareOSFixtureRunner(outputs: [
                .hardware: .init(command: .hardware, stdout: json),
                .displays: .init(command: .displays, stdout: json)
            ])
            let hardware = await HardwareCollector(runner: runner).collect()
            #expect(hardware.section.item("modelName")?.status == .unknown)
            #expect(hardware.section.item("gpuCount")?.status == .unknown)
            #expect(hardware.gpus.isEmpty)
        }
    }

    @Test
    func testSuccessfulEmptyDisplayListIsOnlyAnObservedCount() async throws {
        let runner = HardwareOSFixtureRunner(outputs: [
            .displays: .init(command: .displays, stdout: #"{"SPDisplaysDataType":[]}"#)
        ])
        let hardware = await HardwareCollector(runner: runner).collect()
        let count = try #require(hardware.section.item("gpuCount"))
        #expect(count.value == "0")
        #expect(count.message.contains("physical devices"))
        #expect(hardware.gpus.isEmpty)
    }

    @Test
    func testTimeoutAndNonzeroExitIgnorePartialOutputAndPrivateStderr() async throws {
        var outputs = HardwareOSFixtureRunner.macPro.outputs
        let hardwareFixture = try #require(outputs[.hardware])
        let displaysFixture = try #require(outputs[.displays])
        outputs[.hardware] = .init(command: .hardware, stdout: hardwareFixture.stdout,
                                  stderr: "PRIVATE-USERNAME", exitCode: nil, termination: .timedOut)
        outputs[.displays] = .init(command: .displays, stdout: displaysFixture.stdout,
                                  stderr: "PRIVATE-USERNAME", exitCode: 1)
        let hardware = await HardwareCollector(runner: HardwareOSFixtureRunner(outputs: outputs)).collect()
        #expect(hardware.section.item("modelIdentifier")?.status == .unknown)
        #expect(hardware.section.item("gpuCount")?.status == .unknown)
        #expect(hardware.gpus.isEmpty)
        #expect(hardware.section.item("cpu")?.status == .healthy)
        let encoded = String(decoding: try JSONEncoder().encode(hardware), as: UTF8.self)
        #expect(!(encoded.contains("PRIVATE-USERNAME")))
        #expect(encoded.contains("timedOut"))
    }

    @Test
    func testOSCollectsVersionArchitectureAndReportedBootMode() async throws {
        let os = await OSCollector(runner: HardwareOSFixtureRunner.os).collect()
        #expect(os.id == "os")
        #expect(os.item("productName")?.value == "macOS")
        #expect(os.item("productVersion")?.value == "26.0.1")
        #expect(os.item("buildVersion")?.value == "25A362")
        #expect(os.item("architecture")?.value == "x86_64")
        #expect(os.item("bootMode")?.value == "Normal Boot (normal_boot)")
        #expect(os.items.allSatisfy { !$0.evidence.isEmpty })
        let encoded = String(decoding: try JSONEncoder().encode(os), as: UTF8.self)
        #expect(!(encoded.contains("PRIVATE-USERNAME")))
        #expect(!(encoded.contains("PRIVATE-VOLUME")))
    }

    @Test
    func testMissingBootModeDoesNotDefaultToNormalBoot() async throws {
        var outputs = HardwareOSFixtureRunner.os.outputs
        outputs[.software] = .init(command: .software, stdout: #"{"SPSoftwareDataType":[{"os_version":"macOS 26.0.1 (25A362)"}]}"#)
        let os = await OSCollector(runner: HardwareOSFixtureRunner(outputs: outputs)).collect()
        #expect(os.item("bootMode")?.status == .unknown)
        #expect(os.item("bootMode")?.value == nil)
    }

    @Test
    func testMalformedOSValuesAndCommandFailuresReturnUnknown() async throws {
        let runner = HardwareOSFixtureRunner(outputs: [
            .osName: .init(command: .osName, stdout: "macOS", exitCode: 1),
            .osVersion: .init(command: .osVersion, stdout: "macOS 26"),
            .osBuild: .init(command: .osBuild, stdout: "Unknown"),
            .architecture: .init(command: .architecture, stdout: "unknown-cpu"),
            .software: .init(command: .software, stdout: #"{"SPSoftwareDataType":[{"boot_mode":true}]}"#)
        ])
        let os = await OSCollector(runner: runner).collect()
        #expect(os.items.allSatisfy { $0.status == .unknown && $0.value == nil })
    }

    @Test
    func testAmbiguousHardwareAndSoftwareRowsAreUnknown() async throws {
        let runner = HardwareOSFixtureRunner(outputs: [
            .hardware: .init(command: .hardware, stdout: #"{"SPHardwareDataType":[{"machine_model":"MacPro6,1"},{"machine_model":"MacBookPro11,3"}]}"#),
            .software: .init(command: .software, stdout: #"{"SPSoftwareDataType":[{"boot_mode":"safe_boot"},{"boot_mode":"normal_boot"}]}"#)
        ])
        let hardware = await HardwareCollector(runner: runner).collect()
        let os = await OSCollector(runner: runner).collect()
        #expect(hardware.section.item("modelIdentifier")?.status == .unknown)
        #expect(os.item("bootMode")?.status == .unknown)
    }
}

/// Synthetic fixtures model output shape; they are not reports captured from the user's Macs.
private struct HardwareOSFixtureRunner: CommandExecuting {
    let outputs: [DiagnosticCommand: CommandOutput]
    func run(_ command: DiagnosticCommand) async -> CommandOutput {
        outputs[command] ?? CommandOutput(command: command, exitCode: 1)
    }

    static let macPro = HardwareOSFixtureRunner(outputs: [
        .hardware: .init(command: .hardware, stdout: #"{"SPHardwareDataType":[{"machine_name":"Mac Pro","machine_model":"MacPro6,1","serial_number":"PRIVATE-SERIAL","platform_UUID":"PRIVATE-UUID"}]}"#),
        .displays: .init(command: .displays, stdout: #"{"SPDisplaysDataType":[{"sppci_model":"AMD FirePro D500","spdisplays_vram":"3 GB","spdisplays_metal":"spdisplays_supported"},{"sppci_model":"AMD FirePro D500","spdisplays_vram":"3 GB","spdisplays_metal":"spdisplays_supported"}]}"#),
        .cpu: .init(command: .cpu, stdout: "Intel(R) Xeon(R) CPU E5-2697 v2 @ 2.70GHz\n"),
        .physicalCores: .init(command: .physicalCores, stdout: "12\n"),
        .logicalCores: .init(command: .logicalCores, stdout: "24\n"),
        .memory: .init(command: .memory, stdout: "68719476736\n")
    ])

    static let macBookPro = HardwareOSFixtureRunner(outputs: [
        .hardware: .init(command: .hardware, stdout: #"{"SPHardwareDataType":[{"machine_name":"MacBook Pro","machine_model":"MacBookPro11,3"}]}"#),
        .displays: .init(command: .displays, stdout: #"{"SPDisplaysDataType":[{"sppci_model":"Intel Iris Pro","spdisplays_vram_shared":"1536 MB","spdisplays_metal":"spdisplays_supported"},{"sppci_model":"NVIDIA GeForce GT 750M","spdisplays_vram":"2 GB"}]}"#),
        .cpu: .init(command: .cpu, stdout: "Intel(R) Core(TM) i7-4870HQ CPU @ 2.50GHz"),
        .physicalCores: .init(command: .physicalCores, stdout: "4"),
        .logicalCores: .init(command: .logicalCores, stdout: "8"),
        .memory: .init(command: .memory, stdout: "17179869184")
    ])

    static let os = HardwareOSFixtureRunner(outputs: [
        .osName: .init(command: .osName, stdout: "macOS\n"),
        .osVersion: .init(command: .osVersion, stdout: "26.0.1\n"),
        .osBuild: .init(command: .osBuild, stdout: "25A362\n"),
        .architecture: .init(command: .architecture, stdout: "x86_64\n"),
        .software: .init(command: .software, stdout: #"{"SPSoftwareDataType":[{"boot_mode":"normal_boot","user_name":"PRIVATE-USERNAME","boot_volume":"PRIVATE-VOLUME"}]}"#)
    ])
}
