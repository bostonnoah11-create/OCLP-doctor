/// A dated selection of official guidance. Applicability is not a diagnosis.
/// Entries describe evidence and read-only follow-up; no workaround is executed.
public enum OfficialIssueCatalog {
    public static let reviewedOn = "2026-10-17"

    public static let entries: [KnownIssue] = [
        KnownIssue(
            id: "oclp-tahoe-preliminary-support",
            title: "macOS Tahoe 26 and OpenCore Legacy Patcher Support",
            project: "OpenCore Legacy Patcher",
            upstreamStatus: "Open support tracker; 3.0.0-rc.2 is a prerelease",
            summary: "OCLP 3.0.0 RC provides preliminary Tahoe support, including graphics patches. A version shown as 3.0.0 does not identify whether the installed copy is a release candidate or another build.",
            scope: "OS: macOS Tahoe 26. OCLP: 3.0.0 release candidates. Hardware: AMD legacy GCN; Intel Haswell; NVIDIA Kepler. Limits: These sources do not establish validation for every macOS Tahoe build. The installed 3.0.0 string does not identify an RC tag, stable release, or exact commit.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Note the exact macOS version and build number.",
                "Compare the installed OCLP app, booted EFI, and recorded root-patch versions.",
                "Check any available release or build information against the official release page."
            ],
            sources: [
                IssueSource(title: "macOS Tahoe 26 and OpenCore Legacy Patcher Support", url: "https://github.com/dortania/OpenCore-Legacy-Patcher/issues/1167"),
                IssueSource(title: "3.0.0-rc.2", url: "https://github.com/dortania/OpenCore-Legacy-Patcher/releases/tag/3.0.0-rc.2"),
                IssueSource(title: "2.5.1", url: "https://github.com/dortania/OpenCore-Legacy-Patcher/releases/tag/2.5.1"),
                IssueSource(title: "RC.2 internal patcher_version", url: "https://github.com/dortania/OpenCore-Legacy-Patcher/blob/3.0.0-rc.2/opencore_legacy_patcher/constants.py#L13-L16")
            ]
        ),
        KnownIssue(
            id: "oclp-amd-gcn-chromium",
            title: "AMD GCN GPUs and Chrome Rendering Issues",
            project: "OpenCore Legacy Patcher",
            upstreamStatus: "Open issue",
            summary: "D500 hardware is explicitly included. The report concerns severe application UI rendering corruption, freezing, or unusable Electron UI.",
            scope: "OS: Ventura or newer, as stated in the issue. Software: Chrome 125+; some Electron applications. Hardware: MacPro6,1 FirePro D300/D500/D700; AMD HD 7000; MacBookPro11,5 R9 M370X. Limits: Behavior on individual Tahoe builds and current application versions is not established. The issue does not identify transient whole-screen wake artifacts as its signature.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Record whether corruption is confined to a Chromium/Electron window or affects the entire display.",
                "Record the affected application's name and version.",
                "Note when the display issue occurred and compare existing log entries around that time."
            ],
            sources: [
                IssueSource(title: "AMD GCN GPUs and Chrome Rendering Issues", url: "https://github.com/dortania/OpenCore-Legacy-Patcher/issues/1145")
            ]
        ),
        KnownIssue(
            id: "oclp-legacy-metal-limitations",
            title: "Legacy Metal Graphics Support and macOS Ventura - Sequoia",
            project: "OpenCore Legacy Patcher",
            upstreamStatus: "Open tracker; resolved rows excluded",
            summary: "The tracker lists Haswell/Kepler feature limitations and graphics artifacts, with resolved items crossed out.",
            scope: "OS: Ventura; Sonoma; Sequoia; per-item scope differs. Hardware: Intel Haswell; NVIDIA Kepler; AMD GCN 1-3 including FirePro D500. Limits: The issue title and tables do not validate these individual limitations on Tahoe. A detected GPU family does not prove any listed symptom is present.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Check both GPU models in Hardware.",
                "Compare the affected application feature, macOS version, and symptom with the issue.",
                "Check whether the official tracker marks the matching symptom as resolved."
            ],
            sources: [
                IssueSource(title: "Legacy Metal Graphics Support and macOS Ventura - Sequoia", url: "https://github.com/dortania/OpenCore-Legacy-Patcher/issues/1008")
            ]
        ),
        KnownIssue(
            id: "oclp-update-root-patch-dependencies",
            title: "Updating and post-install patch package requirements",
            project: "OpenCore Legacy Patcher",
            upstreamStatus: "Official preparation guidance",
            summary: "GCN root patching requires a KDK. Haswell/Kepler need MetallibSupportPkg matched to the OS build. Updates can remove root patches; app, EFI and root-patch versions are separate evidence.",
            scope: "OS: AMD GCN: Ventura or newer; Haswell/Kepler MetallibSupportPkg: Sequoia or newer. Hardware: MacPro6,1 FirePro D500; Haswell and NVIDIA Kepler systems. Limits: An installed dependency does not establish that current root patches are applied or valid. Exact host package compatibility has not been checked.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Compare the running macOS build with the recorded patch information.",
                "Review the recorded patcher version, patch date, and package information; these do not confirm that patches currently work.",
                "Check whether an existing patching error identifies a missing package.",
                "Compare the patching error with the official package requirements, removing personal information before sharing it."
            ],
            sources: [
                IssueSource(title: "Updating and post-install patch package requirements", url: "https://dortania.github.io/OpenCore-Legacy-Patcher/POST-INSTALL.html#packages-requiring-networking"),
                IssueSource(title: "MetallibSupportPkg", url: "https://dortania.github.io/OpenCore-Legacy-Patcher/POST-INSTALL.html#metallibsupportpkg"),
                IssueSource(title: "KDK / Kernel Debug Kit", url: "https://dortania.github.io/OpenCore-Legacy-Patcher/POST-INSTALL.html#kdk-kernel-debug-kit"),
                IssueSource(title: "Updating", url: "https://dortania.github.io/OpenCore-Legacy-Patcher/UPDATE.html")
            ]
        ),
        KnownIssue(
            id: "oclp-mbp113-gmux-boot",
            title: "MacBookPro11,3 GMUX issues with 12.0 Beta 7 and newer",
            project: "OpenCore Legacy Patcher",
            upstreamStatus: "Closed historical issue; Monterey guidance remains",
            summary: "When Kepler drivers are unavailable, the documented GMUX display handoff can fail during boot.",
            scope: "OS: Monterey 12.0 beta 7 and later Monterey guidance. OCLP: Kepler acceleration restoration introduced in 0.2.5. Hardware: MacBookPro11,3 with Haswell iGPU and NVIDIA Kepler dGPU. Limits: No exact Tahoe behavior established by this historical issue. Boot black screen is distinct from a short wake artifact.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Confirm model and both GPU identities.",
                "Review the macOS and patch versions, and note whether the black screen occurs during startup or after waking."
            ],
            sources: [
                IssueSource(title: "MacBookPro11,3 GMUX issues with 12.0 Beta 7 and newer", url: "https://github.com/dortania/OpenCore-Legacy-Patcher/issues/522"),
                IssueSource(title: "Black Screen on MacBookPro11,3 in macOS Monterey", url: "https://dortania.github.io/OpenCore-Legacy-Patcher/TROUBLESHOOT-MISC.html#black-screen-on-macbookpro11-3-in-macos-monterey")
            ]
        ),
        KnownIssue(
            id: "oclp-sleep-wake-scope-guard",
            title: "Hibernation Issues with OpenCore",
            project: "OpenCore Legacy Patcher",
            upstreamStatus: "Open historical issue; unrelated TeraScale guidance excluded",
            summary: "This issue concerns hibernation failures. The separate TeraScale 1 wake-distortion guidance does not cover FirePro D500, Haswell, or Kepler graphics.",
            scope: "OS: Historical Big Sur/Monterey hibernation discussion; exact full issue scope unspecified; Separate distortion guidance: macOS 11.3 through Monterey. Hardware: Issue #72: some legacy Macs; authoritative body does not enumerate affected models; Separate distortion guidance: TeraScale 1 HD2000-4000. Limits: No reviewed source confirms MacPro6,1 D500 + Tahoe transient wake corruption. The TeraScale 1 distortion guidance does not apply to FirePro D500 GCN or Haswell/Kepler.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Review Sleep & Wake events and existing diagnostic reports around the time of the problem.",
                "Check whether the records show an explicit failure, hibernation resume, or an ordinary sleep/wake event.",
                "Compare event times with their timezones; nearby events alone do not establish a cause."
            ],
            sources: [
                IssueSource(title: "Hibernation Issues with OpenCore", url: "https://github.com/dortania/OpenCore-Legacy-Patcher/issues/72"),
                IssueSource(title: "TeraScale 1 wake distortion scope", url: "https://dortania.github.io/OpenCore-Legacy-Patcher/TROUBLESHOOT-HARDWARE.html#wake-from-sleep-heavily-distorted-on-ati-amd-terascale-1-from-macos-11-3-to-monterey")
            ]
        ),
        KnownIssue(
            id: "oclp-tahoe-filevault-restored",
            title: "FileVault 2 support restored in the Tahoe release candidate",
            project: "OpenCore Legacy Patcher",
            upstreamStatus: "Release guidance; support restored in the Tahoe RC",
            summary: "OCLP 3.0.0-rc.2 restores FileVault 2 support on Tahoe. FileVault being enabled or disabled does not by itself indicate a fault.",
            scope: "OS: macOS 26. OCLP: 3.0.0-rc.2 release notes. Hardware: No model-specific validation matrix supplied by the cited release. Limits: Host encryption status does not establish boot/recovery readiness. An app reporting 3.0.0 is not sufficient to identify its release candidate.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Check the FileVault status shown in Security.",
                "Compare the installed OCLP app version with the version used to build the booted EFI."
            ],
            sources: [
                IssueSource(title: "FileVault 2 support restored in the Tahoe release candidate", url: "https://github.com/dortania/OpenCore-Legacy-Patcher/releases/tag/3.0.0-rc.2"),
                IssueSource(title: "Tahoe support tracker", url: "https://github.com/dortania/OpenCore-Legacy-Patcher/issues/1167")
            ]
        ),
        KnownIssue(
            id: "oclp-modern-wireless-scope",
            title: "Modern Wireless detection and Tahoe wireless improvements",
            project: "OpenCore Legacy Patcher",
            upstreamStatus: "Official detection and release guidance",
            summary: "Wireless patch requirements depend on the adapter chipset and macOS version. The Tahoe release candidate includes improved wireless patches.",
            scope: "OS: Sonoma and newer for this patch family. Hardware: Detected Broadcom AirPortBrcm4360 or AirportBrcmNIC chipset; source also handles a third-party variant without official support. Limits: Model alone does not establish the installed wireless adapter. This source alone does not establish a connection failure or compatibility with every Tahoe build.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Check the wireless adapter chipset and recorded wireless patches.",
                "Note whether the connection problem began after a macOS update."
            ],
            sources: [
                IssueSource(title: "Modern Wireless detection and Tahoe wireless improvements", url: "https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/patchsets/hardware/networking/modern_wireless.py"),
                IssueSource(title: "3.0.0-rc.2 wireless improvements", url: "https://github.com/dortania/OpenCore-Legacy-Patcher/releases/tag/3.0.0-rc.2")
            ]
        ),
        KnownIssue(
            id: "opencore-nvme-hibernation-path",
            title: "NVMe Mac hibernation device-path repair",
            project: "OpenCore",
            upstreamStatus: "Fixed in OpenCore 1.0.8; affected range not established",
            summary: "OpenCore 1.0.8 repairs an unresolved ATAPI device-path case during hibernation on NVMe Macs.",
            scope: "Hardware: Genuine Macs with NVMe storage. OpenCore: Fix shipped in 1.0.8. OS: Specific macOS versions not stated in release note. Limits: The host storage protocol and affected hibernation device path are not collected. No universal affected version range was established.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Check whether the installed storage uses NVMe and review existing hibernation or startup failures.",
                "If you have an EFI configuration copy, review its hibernation settings."
            ],
            sources: [
                IssueSource(title: "NVMe Mac hibernation device-path repair", url: "https://github.com/acidanthera/OpenCorePkg/releases/tag/1.0.8"),
                IssueSource(title: "ATAPI hibernation path repair", url: "https://github.com/acidanthera/OpenCorePkg/commit/fa14f4f"),
                IssueSource(title: "Official 1.0.8 release workflow", url: "https://github.com/acidanthera/OpenCorePkg/actions/runs/36352833721")
            ]
        ),
        KnownIssue(
            id: "opencore-dmg-secureboot-restore",
            title: "Apple Secure Boot restoration after DMG loading",
            project: "OpenCore",
            upstreamStatus: "Merged fix; shipped in OpenCore 1.0.8",
            summary: "OpenCore 1.0.8 restores Apple Secure Boot verification availability after loading a DMG image.",
            scope: "Software: Apple Secure Boot verification after DMG loading. Hardware: PR reports an installer crash example on unsupported T2 Macs. OS: macOS 26 installer for the reported T2 crash example. Limits: Host SecureBootModel/DmgLoading and DMG boot evidence are unknown. MacPro6,1 is outside the T2 crash example. SIP, authenticated-root and FileVault status do not determine OpenCore Apple Secure Boot policy.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Check SecureBootModel and DmgLoading in an existing EFI configuration copy.",
                "Compare any recorded installer or Recovery startup failure with OCLP's configuration requirements."
            ],
            sources: [
                IssueSource(title: "Apple Secure Boot restoration after DMG loading", url: "https://github.com/acidanthera/OpenCorePkg/pull/610"),
                IssueSource(title: "1.0.8 release", url: "https://github.com/acidanthera/OpenCorePkg/releases/tag/1.0.8"),
                IssueSource(title: "Apple Secure Boot policy and sealed-volume limits", url: "https://github.com/acidanthera/OpenCorePkg/blob/1.0.6/Docs/Configuration.tex#L4192-L4255")
            ]
        ),
        KnownIssue(
            id: "opencore-tahoe-xhciportlimit",
            title: "Tahoe compatibility improvement for XhciPortLimit",
            project: "OpenCore",
            upstreamStatus: "Compatibility improvement released in OpenCore 1.0.7",
            summary: "Release 1.0.7 improves Tahoe compatibility of the XhciPortLimit quirk.",
            scope: "OS: macOS Tahoe 26. Configuration: Kernel/Quirks/XhciPortLimit. OpenCore: Compatibility improvement in 1.0.7. Limits: Host XhciPortLimit setting is uncollected. Display USB errors near wake do not establish a port-limit problem.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Check XhciPortLimit in an existing EFI configuration copy.",
                "Review the listed USB devices, recorded USB errors, and component versions supported by OCLP."
            ],
            sources: [
                IssueSource(title: "Tahoe compatibility improvement for XhciPortLimit", url: "https://github.com/acidanthera/OpenCorePkg/releases/tag/1.0.7")
            ]
        ),
        KnownIssue(
            id: "opencore-gpu-firmware-boot-2126",
            title: "Ventura boot issues with certain GPU and firmware combinations",
            project: "OpenCore",
            upstreamStatus: "Open historical issue; Ventura boot scope",
            summary: "The issue describes early boot stalls around PCI initialization for particular GPU/firmware combinations.",
            scope: "OS: Ventura beta 1 through beta 8 in original report; later Ventura user reports. Hardware: Genuine MacPro6,1 with dual D300 in original report; MacPro6,1 with D500 in a later individual user report. Limits: No confirmed Tahoe scope or universal fixed release is established. The D500 comment is an individual report, not confirmation for all D500 machines.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Compare any recorded startup failure with the macOS version, GPU, and startup stage described in the issue."
            ],
            sources: [
                IssueSource(title: "Ventura boot issues with certain GPU and firmware combinations", url: "https://github.com/acidanthera/bugtracker/issues/2126")
            ]
        ),
        KnownIssue(
            id: "opencore-emulated-nvram-wake-2134",
            title: "Historical wake hang with standalone emulated NVRAM on real Macs",
            project: "OpenCore",
            upstreamStatus: "Closed historical issue; fixed in OpenCore 0.8.6",
            summary: "OpenCore 0.8.6 fixed the wake hang described for a particular emulated NVRAM driver and firmware combination.",
            scope: "Hardware: EFI 1.1 systems including earlier real Macs. Configuration: Standalone OpenVariableRuntimeDxe.efi emulated NVRAM driver. Limits: The host driver presence/version and EFI 1.1 applicability are uncollected. OpenCore version does not establish every installed standalone driver version.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "If waking hangs in the same way, review enabled driver names and versions in an existing EFI copy."
            ],
            sources: [
                IssueSource(title: "Historical wake hang with standalone emulated NVRAM on real Macs", url: "https://github.com/acidanthera/bugtracker/issues/2134"),
                IssueSource(title: "0.8.6 wake fix", url: "https://github.com/acidanthera/OpenCorePkg/releases/tag/0.8.6")
            ]
        ),
        KnownIssue(
            id: "opencore-config-picker-version",
            title: "Match picker/configuration validation to the booted OpenCore version",
            project: "OpenCore",
            upstreamStatus: "Version-specific validation guidance",
            summary: "OpenCore 1.0.6 validation checks that an enabled OpenCanopy driver uses External PickerMode. Passing validation does not guarantee successful startup.",
            scope: "OpenCore: Validation rules verified for 1.0.6. Configuration: OpenCanopy.efi and Misc/Boot/PickerMode. Limits: No active EFI configuration or mixed-component defect has been observed. A supplied EFI copy is not automatically the booted copy.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Check the validator version before using it to inspect a local configuration copy.",
                "Review the boot picker driver and resource files in that copy."
            ],
            sources: [
                IssueSource(title: "Match picker/configuration validation to the booted OpenCore version", url: "https://github.com/acidanthera/OpenCorePkg/blob/1.0.6/Utilities/ocvalidate/README.md"),
                IssueSource(title: "OpenCanopy and PickerMode consistency check", url: "https://github.com/acidanthera/OpenCorePkg/blob/1.0.6/Utilities/ocvalidate/ValidateMisc.c#L246-L264"),
                IssueSource(title: "Validation limitations", url: "https://github.com/acidanthera/OpenCorePkg/blob/1.0.6/Docs/Configuration.tex#L373-L376")
            ]
        ),
        KnownIssue(
            id: "opencore-oem-identity-evidence",
            title: "Separate preserved OEM identity evidence from the exposed model",
            project: "OpenCore",
            upstreamStatus: "Official identity interpretation guidance",
            summary: "The model reported by macOS can differ from the OEM identifier preserved by OpenCore. The preserved value is not authenticated factory identity.",
            scope: "Configuration: ExposeSensitiveData bit 0x08; oem-product SMBIOS Type 1 ProductName; ForceOcWriteFlash. Limits: Preserved firmware values are not authenticated factory identity. Absence cannot establish spoofing or absence of OpenCore.",
            reviewedOn: reviewedOn,
            nextSteps: [
                "Compare the hardware model readings and the source shown for each."
            ],
            sources: [
                IssueSource(title: "Separate preserved OEM identity evidence from the exposed model", url: "https://github.com/acidanthera/OpenCorePkg/blob/1.0.6/Docs/Configuration.tex#L4054-L4085"),
                IssueSource(title: "ForceOcWriteFlash persistence", url: "https://github.com/acidanthera/OpenCorePkg/blob/1.0.6/Docs/Configuration.tex#L8361-L8365")
            ]
        )
    ]
}
