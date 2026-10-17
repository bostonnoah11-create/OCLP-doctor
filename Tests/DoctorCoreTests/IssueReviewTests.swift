import Foundation
import Testing
@testable import DoctorCore

@Suite
struct IssueReviewTests {
    private let time = Date(timeIntervalSince1970: 1_792_240_000)

    private func snapshot(os: String? = "26.7.1", build: String? = "25G241", gpu: String? = "AMD FirePro D500",
                          oc: String? = "REL-106-2025-11-03", oclp: String? = "3.0.0", patchOS: String? = nil,
                          events: [SleepWakeEvent] = [], coverage: LogCoverageState = .available,
                          model: String = "MacPro6,1", unknownGPU: Bool = false) -> SystemInfo {
        func item(_ id: String, _ value: String?, _ status: DiagnosticStatus = .healthy) -> DiagnosticItem {
            DiagnosticItem(id: id, label: id, value: value, status: status)
        }
        let gpus = gpu.map { [GPUInfo(id: "gpu", name: item("gpu-name", unknownGPU ? nil : $0), vram: item("vram", nil), metal: item("metal", "Support reported"))] } ?? []
        return SystemInfo(capturedAt: time, duration: 1,
            hardware: HardwareInfo(section: DiagnosticSection(id: "hardware", title: "Hardware", items: [item("modelIdentifier", model)]), gpus: gpus),
            os: DiagnosticSection(id: "os", title: "macOS", items: [item("productVersion", os), item("buildVersion", build)]),
            boot: DiagnosticSection(id: "boot", title: "Boot", items: [item("openCoreVersion", oc), item("oclpBootVersion", oclp)]),
            security: DiagnosticSection(id: "security", title: "Security", items: [item("sip", "Disabled"), item("fileVault", "On")]),
            patches: DiagnosticSection(id: "patches", title: "Patches", items: [item("rootPatchOS", patchOS), item("rootPatchState", "Metadata found · validity unverified", .unknown)]),
            sleepWake: SleepWakeReport(windowStart: time.addingTimeInterval(-604800), windowEnd: time, events: events,
                sources: [LogSourceCoverage(id: "logs", name: "Test logs", state: coverage, detail: "Synthetic evidence", evidence: [])]))
    }

    private func event(kind: SleepWakeKind, severity: LogSeverity, title: String = "Example event") -> SleepWakeEvent {
        SleepWakeEvent(id: title, timestamp: time, kind: kind, severity: severity, title: title,
            detail: "Synthetic evidence", source: "Fixture", evidence: [])
    }

    @Test func faultLevelCompletionTracesAreNotRecordedProblems() {
        let review = snapshot(events: [event(kind: .relatedRecord, severity: .fault, title: "Graphics operation completed")]).issueReview
        #expect(!review.findings.contains { $0.kind == .recordedProblem })
    }

    @Test func explicitFailuresAndErrorsPrecedeCompatibilityAndUnknowns() {
        let review = snapshot(events: [event(kind: .relatedError, severity: .error), event(kind: .failure, severity: .error, title: "Sleep Wake Failure")], coverage: .partial).issueReview
        #expect(review.findings.first?.id == "recorded-transition-failures")
        #expect(review.findings.dropFirst().first?.id == "recorded-related-errors")
        let lastProblem = review.findings.lastIndex { $0.kind == .recordedProblem }!
        let firstReview = review.findings.firstIndex { $0.kind == .compatibilityReview }!
        let lastReview = review.findings.lastIndex { $0.kind == .compatibilityReview }!
        let firstGap = review.findings.firstIndex { $0.kind == .evidenceGap }!
        #expect(lastProblem < firstReview && lastReview < firstGap)
        #expect(review.findings.first?.detail.contains(LogTimestamp.display(time)) == true)
    }

    @Test func wakeReasonPermissionDenialIsNotTransitionFailure() {
        let review = snapshot(events: [event(kind: .relatedError, severity: .error, title: "Wake-reason API permission error")]).issueReview
        let problems = review.findings.filter { $0.kind == .recordedProblem }
        #expect(problems.count == 1)
        #expect(problems[0].id == "recorded-wake-permission-errors")
        #expect(problems[0].detail.contains("not proof"))
    }

    @Test func allUnavailableEvidenceNeverProducesCompatibilityOrFailureVerdict() {
        let review = DemoData.snapshot(model: .unavailable).issueReview
        #expect(!review.findings.isEmpty)
        #expect(review.findings.allSatisfy { $0.kind == .evidenceGap })
        #expect(review.findings.contains { $0.id == "issue-scope-gap" })
    }

    @Test func tahoeVersionDoesNotEstablishStableOCLPOrWakeCause() {
        let review = snapshot().issueReview
        let tahoe = review.findings.first { $0.id == "review-tahoe-support" }
        #expect(tahoe?.kind == .compatibilityReview)
        #expect(tahoe?.detail.contains("cannot identify the release channel") == true)
        #expect(!review.findings.contains { $0.kind == .recordedProblem })
        #expect(review.findings.first { $0.id == "review-gcn-app-rendering" }?.detail.contains("does not explain") == true)
    }

    @Test func modelAloneDoesNotMatchGCNAndAmbiguousIntelNameDoesNotMatchHaswell() {
        #expect(!snapshot(gpu: nil, model: "MacPro6,1").issueReview.findings.contains { $0.id == "review-gcn-app-rendering" })
        #expect(!snapshot(os: "14.7", gpu: "Intel Iris Pro").issueReview.findings.contains { $0.id == "review-legacy-metal" })
        #expect(snapshot(os: "14.7", gpu: "Intel Iris Pro 5200").issueReview.findings.contains { $0.id == "review-legacy-metal" })
        #expect(snapshot(os: "14.7", gpu: "Intel Iris Pro Graphics 5200").issueReview.findings.contains { $0.id == "review-legacy-metal" })
        #expect(!snapshot(os: "14.7", gpu: "AMD Radeon HD 7350").issueReview.findings.contains { $0.id == "review-gcn-app-rendering" })
        #expect(snapshot(unknownGPU: true).issueReview.findings.contains { $0.id == "issue-scope-gap" })
    }

    @Test func spoofedReportedModelDoesNotSuppressObservedGPUReview() {
        #expect(snapshot(model: "MacPro7,1").issueReview.findings.contains { $0.id == "review-gcn-app-rendering" })
    }

    @Test func legacyMetalTrackerDoesNotExtendVenturaSequoiaRowsToTahoe() {
        #expect(!snapshot(gpu: "NVIDIA GeForce GT 750M").issueReview.findings.contains { $0.id == "review-legacy-metal" })
        #expect(snapshot(os: "15.7", gpu: "NVIDIA GeForce GT 750M").issueReview.findings.contains { $0.id == "review-legacy-metal" })
        #expect(!snapshot(os: "12.7", gpu: "AMD FirePro D500").issueReview.findings.contains { $0.id == "review-gcn-app-rendering" })
    }

    @Test func comparesBuildTokensNotDarwinAgainstProductVersion() {
        #expect(!snapshot(patchOS: "25.6 (25G241)").issueReview.findings.contains { $0.id == "review-root-patch-build" })
        let mismatch = snapshot(patchOS: "25.5 (25F100)").issueReview.findings.first { $0.id == "review-root-patch-build" }
        #expect(mismatch?.kind == .compatibilityReview)
        #expect(mismatch?.detail.contains("not that current patches are missing or broken") == true)
        #expect(!snapshot(build: nil, patchOS: "25.5 (25F100)").issueReview.findings.contains { $0.id == "review-root-patch-build" })
        #expect(!snapshot(patchOS: "unrecognized 25F100").issueReview.findings.contains { $0.id == "review-root-patch-build" })
    }

    @Test func newerOpenCoreIsReviewNotVersionOnlyBugVerdict() {
        let old = snapshot().issueReview.findings.first { $0.id == "review-opencore-release" }
        #expect(old?.kind == .compatibilityReview)
        #expect(old?.detail.contains("does not establish") == true)
        for value in ["REL-108-2026-09-27", "DBG-109-2026-10-17"] {
            #expect(!snapshot(oc: value).issueReview.findings.contains { $0.id == "review-opencore-release" })
        }
        for value in ["UNK-000-0000-00-00", "REL-1010-2026-10-17", "1.0.6 arbitrary text"] {
            #expect(snapshot(oc: value).issueReview.findings.contains { $0.id == "boot-version-gap" })
            #expect(!snapshot(oc: value).issueReview.findings.contains { $0.id == "review-opencore-release" })
        }
    }

    @Test func reducedSIPFileVaultAndClosedIssuesDoNotBecomeErrors() {
        let review = snapshot(model: "MacBookPro11,3").issueReview
        #expect(!review.findings.contains { $0.kind == .recordedProblem })
        #expect(!review.findings.contains { $0.id.contains("gmux") || $0.id.contains("emulated-nvram") || $0.id.contains("filevault") })
        #expect(review.catalog.contains { $0.id == "oclp-mbp113-gmux-boot" && $0.upstreamStatus.lowercased().contains("closed") })
        #expect(review.catalog.contains { $0.id == "opencore-emulated-nvram-wake-2134" && $0.upstreamStatus.contains("0.8.6") })
    }

    @Test func incompleteCoverageRemainsVisibleEvenWithoutErrors() {
        let review = snapshot(coverage: .partial).issueReview
        #expect(review.findings.contains { $0.id == "log-coverage-gap" && $0.kind == .evidenceGap })
        #expect(!review.findings.contains { $0.kind == .recordedProblem })
    }

    @Test func reportAndJSONIncludeReviewBeforeObservedHardware() throws {
        let result = snapshot(events: [event(kind: .relatedError, severity: .error)])
        let report = ReportGenerator.generate(result)
        #expect(report.range(of: "[Needs your attention]")!.lowerBound < report.range(of: "[Hardware]")!.lowerBound)
        #expect(report.contains("[Official issue catalog]"))
        let data = try JSONEncoder().encode(result)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let review = try #require(json["issueReview"] as? [String: Any])
        #expect((review["catalog"] as? [Any])?.count == 15)
        let decoded = try JSONDecoder().decode(SystemInfo.self, from: data)
        #expect(decoded.issueReview == result.issueReview)
        // Older reports and untrusted serialized reviews both derive findings from observations.
        json.removeValue(forKey: "issueReview")
        let legacy = try JSONDecoder().decode(SystemInfo.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.issueReview == result.issueReview)
        json["issueReview"] = ["findings": ["All healthy"]]
        let untrusted = try JSONDecoder().decode(SystemInfo.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(untrusted.issueReview == result.issueReview)
    }

    @Test func catalogIsDatedUniqueAndUsesOfficialReferencesOnly() throws {
        let entries = OfficialIssueCatalog.entries
        #expect(entries.count == 15)
        #expect(Set(entries.map(\.id)).count == entries.count)
        for entry in entries {
            #expect(entry.reviewedOn == "2026-10-17")
            #expect(!entry.sources.isEmpty && !entry.scope.isEmpty && !entry.nextSteps.isEmpty)
            for source in entry.sources {
                let url = try #require(URL(string: source.url))
                #expect(url.scheme == "https")
                #expect(["github.com", "raw.githubusercontent.com", "dortania.github.io"].contains(url.host ?? ""))
                if url.host == "github.com" || url.host == "raw.githubusercontent.com" {
                    #expect(url.path.hasPrefix("/dortania/") || url.path.hasPrefix("/acidanthera/"))
                }
            }
        }
    }
}
