import Foundation
import Testing
@testable import DoctorCore

@Suite
struct ReportTests {
    @Test func testNilAndBlankValuesCannotBeHealthy() {
        for value in [nil, "", " \n\t"] as [String?] {
            let item = DiagnosticItem(id: "missing", label: "Missing", value: value, status: .healthy)
            #expect(item.status == .unknown)
            #expect(item.displayValue == "Unknown")
        }
    }

    @Test func testBothTargetDemosClearlyDistinguishSyntheticData() {
        for model in [DemoModel.macPro, .macBookPro] {
            let result = DemoData.snapshot(model: model)
            let report = ReportGenerator.generate(result)
            #expect(result.isDemo)
            #expect(result.hardware.gpus.count == 2)
            #expect(report.contains("DEMO / synthetic"))
            #expect(report.contains("Synthetic fixture"))
            #expect(result.patches.item("rootPatchState")?.status == .unknown)
        }
    }

    @Test func testAllUnavailableDemoRemainsUnknown() {
        let result = DemoData.snapshot(model: .unavailable)
        #expect(!(result.items.isEmpty))
        #expect(result.items.allSatisfy { $0.status == .unknown })
        #expect(ReportGenerator.generate(result).contains("Unknown"))
    }

    @Test func testSnapshotCanRoundTripThroughJSON() throws {
        let result = DemoData.snapshot(model: .macPro)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SystemInfo.self, from: data)
        #expect(decoded.hardware == result.hardware)
        #expect(decoded.boot == result.boot)
    }
}
