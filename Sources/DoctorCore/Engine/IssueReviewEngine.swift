import Foundation

/// Conservative, deterministic rules over already collected evidence. No new commands, network or writes.
public enum IssueReviewEngine {
    public static func review(_ snapshot: SystemInfo) -> IssueReview {
        let catalog = OfficialIssueCatalog.entries
        var findings: [IssueFinding] = []
        func sources(_ ids: [String]) -> [IssueSource] {
            var result: [IssueSource] = []
            for source in catalog.filter({ ids.contains($0.id) }).flatMap(\.sources) where !result.contains(source) {
                result.append(source)
            }
            return result
        }
        func add(_ id: String, _ title: String, _ detail: String, kind: FindingKind,
                 priority: FindingPriority = .medium, page: String, evidence: [Evidence] = [],
                 references: [String] = [], steps: [String]) {
            findings.append(IssueFinding(id: id, title: title, detail: detail, nextSteps: steps,
                kind: kind, priority: priority, sources: sources(references), evidence: evidence, relatedPage: page))
        }
        func observation(_ item: DiagnosticItem?) -> [Evidence] {
            guard let item else { return [] }
            return [Evidence(source: item.label, detail: item.displayValue)] + item.evidence
        }
        if let logs = snapshot.sleepWake {
            let failures = logs.events.filter { $0.kind == .failure }
            func logFinding(_ events: [SleepWakeEvent], id: String, title: String, detail: String,
                            priority: FindingPriority, references: [String] = []) {
                guard let latest = events.max(by: { $0.timestamp < $1.timestamp }) else { return }
                let evidence = events.sorted { $0.timestamp > $1.timestamp }.prefix(3).map {
                    Evidence(source: "\(LogTimestamp.display($0.timestamp)) · \($0.source)", detail: "\($0.title): \($0.detail)")
                }
                add(id, title, "\(events.count) retained record(s); latest \(LogTimestamp.display(latest.timestamp)). \(detail) Counts are records, not unique incidents, and do not establish a current failure.",
                    kind: .recordedProblem, priority: priority, page: "sleepWake", evidence: evidence,
                    references: references, steps: ["Open Sleep & Wake for exact timestamps, surrounding events and collection limits.",
                        "Compare the recorded time with the symptom. Temporal proximity does not establish its cause."])
            }
            logFinding(failures, id: "recorded-transition-failures", title: "Sleep/wake failure signatures were recorded",
                detail: "These records contain explicit failure signatures. Their cause is unconfirmed.", priority: .high,
                references: ["oclp-sleep-wake-scope-guard"])
            var seenBluetooth = Set<String>()
            let hciFailures = (logs.events + (logs.focusedWake?.events ?? [])).filter {
                $0.bluetoothEvent == .hciFailure && seenBluetooth.insert($0.id).inserted
            }
            logFinding(hciFailures, id: "recorded-bluetooth-hci", title: "Bluetooth HCI failure signatures were recorded",
                detail: "Explicit failure content was found; source log levels may differ. " + (logs.focusedWake?.bluetoothSummary.detail ?? "Daemon restart and functional recovery remain unverified."),
                priority: .high)
            for group in logs.errorGroups where group.category != .transitionFailure && group.category != .bluetoothHCI {
                let category = group.category
                let id: String
                switch category {
                case .wakePermission: id = "recorded-wake-permission-errors"
                case .other: id = "recorded-related-errors"
                default: id = "recorded-" + String(describing: category)
                }
                logFinding(logs.events.filter { $0.errorCategory == category }, id: id,
                    title: group.title, detail: group.interpretation,
                    priority: category == .wakePermission || category == .usbExclusiveAccess ? .low : .medium)
            }
            if logs.hasIncompleteCoverage {
                let focusedState = logs.focusedWake.map {
                    $0.hasIncompleteCoverage ? "The latest-wake query also has gaps. " : "The latest-wake query completed; the wider history or displayed history still has gaps. "
                } ?? "No latest-wake query was available. "
                add("log-coverage-gap", "Sleep/wake evidence is incomplete",
                    focusedState + "Retention, permissions, collection deadlines or record limits can hide events. Absence of a matching error is not proof of a successful resume.",
                    kind: .evidenceGap, priority: .medium, page: "sleepWake",
                    evidence: (logs.sources + (logs.focusedWake.map { [$0.coverage] } ?? [])).filter { $0.state != .available }.map { Evidence(source: $0.name, detail: $0.detail) }
                        + [Evidence(source: "Event retention", detail: "\(logs.omittedEventCount) event(s) omitted by the display limit.")],
                    steps: ["Check each source's coverage on Sleep & Wake.", "After a recurrence, record the time and duration and refresh the scan while recent logs are still available."])
            }
        } else {
            add("log-coverage-gap", "Sleep/wake evidence is unavailable", "No sleep/wake report was collected.",
                kind: .evidenceGap, page: "sleepWake", steps: ["Refresh diagnostics to request recent sleep/wake evidence."])
        }

        // Preserve explicit collector attention states, without duplicating the timeline findings.
        for section in snapshot.sections where section.id != "sleepWake" {
            for item in section.items where item.status == .attention {
                add("observation-\(section.id)-\(item.id)", item.label, "\(item.displayValue). \(item.message)",
                    kind: .recordedProblem, page: section.id == "security" || section.id == "boot" ? "bootSecurity"
                        : (section.id.hasPrefix("memory") || section.id.hasPrefix("gpu") || section.id == "os" ? "hardware" : section.id),
                    evidence: observation(item), steps: ["Review the collected evidence before considering any change."])
            }
        }

        let osVersion = snapshot.os.item("productVersion")
        let osMajor = majorVersion(osVersion?.value)
        let gpuNames = snapshot.hardware.gpus.compactMap { $0.name.value }
        // Only observed GPU names select GPU scope. A model name alone may be spoofed or customized.
        let hasGCN = gpuNames.contains { $0.range(of: #"(?i)\bFirePro D[357]00\b|\bRadeon.*\bR9 M370X\b"#, options: .regularExpression) != nil }
        let hasHaswell = gpuNames.contains { $0.range(of: #"(?i)\bIntel.*(?:Iris Pro(?: Graphics)? 5200|Iris 5100|HD Graphics 4[246]00|Haswell)\b"#, options: .regularExpression) != nil }
        let hasKepler = gpuNames.contains { $0.range(of: #"(?i)\bNVIDIA.*(?:GT 750M|GT 650M|GTX 680(?:MX|M)?|Kepler)\b"#, options: .regularExpression) != nil }
        let gpuEvidence = snapshot.hardware.gpus.flatMap { observation($0.name) }
        let oclpEvidence = observation(snapshot.boot.item("oclpBootVersion")) + observation(snapshot.patches.item("installedOCLP"))
        let hasOCLPEvidence = [snapshot.boot.item("oclpBootVersion"), snapshot.patches.item("installedOCLP"), snapshot.patches.item("rootPatchVersion")]
            .contains { $0?.value != nil }
        if osMajor == 26 && hasOCLPEvidence {
            add("review-tahoe-support", "Tahoe support needs release-specific review",
                "The official tracker describes preliminary support and 3.0.0-rc.2 is a prerelease. A local 3.0.0 string cannot identify the release channel or exact commit. The reviewed sources do not validate every Tahoe build.",
                kind: .compatibilityReview, priority: .high, page: "knownIssues",
                evidence: observation(osVersion) + observation(snapshot.os.item("buildVersion")) + oclpEvidence,
                references: ["oclp-tahoe-preliminary-support"],
                steps: ["Compare the exact macOS build and trusted OCLP release provenance with the official tracker.",
                    "Keep the installed app, EFI build and root-patch versions separate when reviewing support."])
        }
        if hasGCN, let osMajor, osMajor >= 13 {
            add("review-gcn-app-rendering", "Related AMD GCN application-rendering issue",
                "The observed GPU family is listed in the open Chromium/Electron rendering issue. Application versions and an application-specific symptom match have not been collected. This does not explain brief whole-display corruption after wake.",
                kind: .compatibilityReview, priority: .low, page: "knownIssues", evidence: gpuEvidence + observation(osVersion),
                references: ["oclp-amd-gcn-chromium"],
                steps: ["Record whether corruption affects an application window or the whole display.",
                    "For application-specific symptoms, compare that application's version and behavior with the official issue."])
        }
        if hasHaswell || hasKepler || hasGCN, let osMajor, (13...15).contains(osMajor) {
            add("review-legacy-metal", "Legacy Metal feature limitations may apply",
                "An observed GPU family appears in the Ventura–Sequoia tracker. Individual rows have different OS and feature scopes; resolved rows are not current warnings. No listed functional failure is established by GPU detection alone.",
                kind: .compatibilityReview, priority: .low, page: "knownIssues", evidence: gpuEvidence + observation(osVersion),
                references: ["oclp-legacy-metal-limitations"], steps: ["Match the exact OS, application feature and symptom to an unresolved tracker row."])
        }
        let patchOS = snapshot.patches.item("rootPatchOS")
        let runningBuild = snapshot.os.item("buildVersion")
        let recordedBuild = patchOS?.value.flatMap(patchBuild)
        let actualBuild = runningBuild?.value.flatMap { SafeObservation.matches($0, #"^[0-9]{1,3}[A-Z][0-9]{1,6}[a-z]?$"#) ? $0 : nil }
        let buildMismatch = recordedBuild != nil && actualBuild != nil && recordedBuild != actualBuild
        if buildMismatch {
            add("review-root-patch-build", "Root-patch metadata names a different OS build",
                "The recorded patch build \(recordedBuild!) differs from the running build \(actualBuild!). This proves a metadata mismatch, not that current patches are missing or broken. The leading version in patch OS metadata is Darwin, not the macOS product version.",
                kind: .compatibilityReview, priority: .high, page: "patches",
                evidence: observation(patchOS) + observation(runningBuild), references: ["oclp-update-root-patch-dependencies"],
                steps: ["Review the patch date, exact build and any explicit patching error together.", "Consult the official update and matching-package requirements before planning a separate repair."])
        } else if hasOCLPEvidence, let osMajor, (hasGCN || hasHaswell) && osMajor >= 13 || hasKepler && osMajor >= 12 {
            add("root-patch-validation-gap", "Root-patch operation remains unverified",
                "This GPU/OS combination needs patch preparation review. Patch metadata and reported Metal support do not verify working acceleration. Required KDK or Metallib packages and their exact compatibility have not been inspected.",
                kind: .evidenceGap, priority: .low, page: "patches",
                evidence: observation(snapshot.patches.item("rootPatchState")) + observation(patchOS),
                references: ["oclp-update-root-patch-dependencies"],
                steps: ["Review the official package requirements for the observed GPU and exact OS build.", "Preserve any explicit patching failure separately from metadata availability."])
        }
        let ocItem = snapshot.boot.item("openCoreVersion")
        if let version = openCoreVersion(ocItem?.value), version < 108 {
            add("review-opencore-release", "A newer OpenCore release has relevant fixes to review",
                "The exposed version predates the reviewed 1.0.8 release. Its fixes have specific configuration and hardware conditions; this does not establish that this Mac is affected or should use a standalone OpenCore update. OCLP manages its own bundled bootloader.",
                kind: .compatibilityReview, priority: .medium, page: "knownIssues", evidence: observation(ocItem),
                references: ["opencore-nvme-hibernation-path", "opencore-dmg-secureboot-restore", "opencore-tahoe-xhciportlimit"], steps: ["Review the OpenCore 1.0.8 release notes in Known Issues, including each fix's conditions.",
                    "Check the matching OCLP release and its bundled OpenCore before planning any update."])
        } else if openCoreVersion(ocItem?.value) == nil {
            add("boot-version-gap", "OpenCore release comparison is unavailable",
                "The exposed boot version is absent, hidden or cannot be compared safely. An installed OCLP application does not identify the active bootloader.",
                kind: .evidenceGap, priority: .low, page: "bootSecurity", evidence: observation(ocItem),
                steps: ["Review Boot & Security for the available boot evidence and its collection status."])
        }
        if osMajor == nil || gpuNames.isEmpty || gpuNames.count != snapshot.hardware.gpus.count {
            add("issue-scope-gap", "Hardware or OS scope could not be matched",
                "Missing or unrecognized OS/GPU observations prevent reliable matching of hardware-specific official issues. No compatibility verdict is available.",
                kind: .evidenceGap, page: "hardware", evidence: observation(osVersion) + gpuEvidence,
                steps: ["Review Hardware and macOS observations, then refresh any failed collections."])
        }
        add("catalog-coverage-gap", "Some official issue conditions require additional evidence",
            "This scan does not inspect the active EFI configuration, storage controller or wireless chipset, and does not functionally test graphics, FileVault recovery or hibernation. Those catalog entries remain conditional. A curated catalog cannot cover every possible problem.",
            kind: .evidenceGap, priority: .low, page: "knownIssues",
            steps: ["Use Known Issues to review each condition, upstream state and safe next check.",
                "Before a future OS or bootloader change, review the official update guidance and confirm your backup and recovery plan separately."])

        let kindOrder: [FindingKind: Int] = [.recordedProblem: 0, .compatibilityReview: 1, .evidenceGap: 2]
        let priorityOrder: [FindingPriority: Int] = [.high: 0, .medium: 1, .low: 2]
        findings.sort {
            let left = (kindOrder[$0.kind]!, priorityOrder[$0.priority]!, $0.id)
            let right = (kindOrder[$1.kind]!, priorityOrder[$1.priority]!, $1.id)
            return left < right
        }
        return IssueReview(reviewedOn: OfficialIssueCatalog.reviewedOn, findings: findings, catalog: catalog)
    }

    static func majorVersion(_ value: String?) -> Int? {
        guard let value, SafeObservation.matches(value, #"^[0-9]{1,3}(\.[0-9]{1,3}){1,2}$"#) else { return nil }
        return value.split(separator: ".").first.flatMap { Int($0) }
    }

    static func openCoreVersion(_ value: String?) -> Int? {
        // Three-digit historical compact versions are unambiguous. Longer encodings need a separate parser.
        guard let value, SafeObservation.matches(value, #"^(REL|DBG|NOOPT)-[0-9]{3}-[0-9]{4}-[0-9]{2}-[0-9]{2}$"#) else { return nil }
        return Int(value.split(separator: "-")[1])
    }

    private static func patchBuild(_ value: String) -> String? {
        guard SafeObservation.matches(value, #"^[0-9]{1,3}\.[0-9]{1,3} \([0-9]{1,3}[A-Z][0-9]{1,6}[a-z]?\)$"#),
              let opening = value.firstIndex(of: "(") else { return nil }
        return String(value[value.index(after: opening)..<value.index(before: value.endIndex)])
    }
}
