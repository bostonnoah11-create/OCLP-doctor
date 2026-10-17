# Official issue review

Reviewed on **2026-10-17**. This is a bundled, offline selection of official Dortania and Acidanthera issues, releases, documentation, and source code. It supports review of MacPro6,1 with AMD FirePro D500 and MacBookPro11,3 with Intel Haswell/NVIDIA Kepler, plus conditional bootloader scenarios.

The catalog contains **15 records: eight OCLP and seven OpenCore records**. It is not an exhaustive list and cannot detect or guarantee an explanation for every problem. An open repository issue or matching hardware family does not confirm that an issue occurred on this Mac. Unknown, inaccessible, or missing evidence is not evidence that the system is healthy.

## How the app uses the catalog

The Overview prioritizes recorded problems, compatibility reviews, and evidence gaps before informational readings. An upstream issue is contextual guidance until the matching local symptom or failure is observed. Keep source status, applicable scope, and the review date visible; historical fixes must not become current warnings merely because the machine model matches.

The catalog is reviewed manually and performs no network requests. Confirming that a particular issue occurred requires matching hardware, OS, symptom, and any relevant configuration. Partial matches appear only as compatibility reviews with their missing conditions stated. Version age alone does not establish an affected system. A closed issue can be useful historical context without describing a present defect.

Safe follow-up means inspecting existing versions, hardware, metadata, bounded/redacted logs, a supplied configuration copy, or an official source. A supplied EFI copy is not necessarily the booted EFI. Upstream pages may contain destructive commands, setting changes, or experimental workarounds; these are not executable app actions. Doctor does not download or install patches or modify EFI, NVRAM, SIP, FileVault, power, graphics, or network settings.

## Important scope exclusions

- **Tahoe has preliminary support.** The updated [Tahoe tracker](https://github.com/dortania/OpenCore-Legacy-Patcher/issues/1167) describes OCLP 3.0.0 RC support. [3.0.0-rc.2](https://github.com/dortania/OpenCore-Legacy-Patcher/releases/tag/3.0.0-rc.2) is a prerelease; the stable endpoint resolved to [2.5.1](https://github.com/dortania/OpenCore-Legacy-Patcher/releases/tag/2.5.1) at review. These sources do not establish validation for every macOS Tahoe build.
- **A 3.0.0 version string does not establish release channel.** The [RC.2 constants](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/3.0.0-rc.2/opencore_legacy_patcher/constants.py#L13-L16) use that plain value. Installed app, booted EFI, and root-patch versions remain separate evidence.
- **FileVault is not a blanket Tahoe error.** RC.2 restores support. Encryption status alone does not demonstrate a boot or patching fault.
- **D500 Chromium corruption is not a confirmed cause of transient wake artifacts.** Chromium rendering corruption and transient whole-screen wake artifacts have different symptom descriptions. A matching GPU alone does not establish a shared cause, a hardware fault, or a patch failure.
- **Do not transplant older graphics workarounds.** TeraScale 1 distortion on Big Sur/Monterey does not match D500 GCN or Haswell/Kepler. The MacBookPro11,3 GMUX issue is historical Monterey boot guidance. Individual Ventura–Sequoia Metal limitations are not verified Tahoe behavior.
- **Metadata does not prove patch validity.** KDK/Metallib applicability, package presence, and patch records do not establish working acceleration. Missing metadata remains unknown. Wireless guidance needs chipset evidence rather than a model-only assumption.
- **OpenCore fixes need prerequisites.** The reviewed [1.0.8 release](https://github.com/acidanthera/OpenCorePkg/releases/tag/1.0.8) contains specific fixes; this is not an instruction to replace OCLP-managed components. Being older than a fix is only one possible prerequisite. The NVMe path, DMG/Secure Boot policy, or XhciPortLimit condition must also be established. The historical emulated-NVRAM wake issue is fixed in 0.8.6 and must not be flagged from a newer 1.0.6 bootloader version.
- **Logs need context.** A timestamp correlation is not a cause. A Fault-level trace without explicit failure content is not a confirmed failure. An empty bounded scan does not establish successful wake or healthy graphics.

## Catalog records

Stable IDs match the bundled Swift catalog. Known scope and remaining limits are preserved for each entry. Source pages can change after review.

### oclp-tahoe-preliminary-support

**Open support tracker; 3.0.0-rc.2 is a prerelease.** [macOS Tahoe 26 and OpenCore Legacy Patcher Support](https://github.com/dortania/OpenCore-Legacy-Patcher/issues/1167). The current tracker describes preliminary Tahoe support. RC.2 is explicitly a prerelease; its code reports patcher_version 3.0.0. Its release notes include Tahoe graphics support. Treat older blanket statements that Tahoe is unsupported as stale.

Scope: OS: macOS Tahoe 26. OCLP: 3.0.0 release candidates. Hardware: AMD legacy GCN; Intel Haswell; NVIDIA Kepler.

Limits: These sources do not establish validation for every macOS Tahoe build. The installed 3.0.0 string does not identify an RC tag, stable release, or exact commit.

Read-only follow-up: Retain exact sw_vers product version and build. Show installed app, booted EFI and root-patch versions separately. Compare any available trusted build provenance with the official RC tag.

Additional sources: [3.0.0-rc.2](https://github.com/dortania/OpenCore-Legacy-Patcher/releases/tag/3.0.0-rc.2), [2.5.1](https://github.com/dortania/OpenCore-Legacy-Patcher/releases/tag/2.5.1), [RC.2 internal patcher_version](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/3.0.0-rc.2/opencore_legacy_patcher/constants.py#L13-L16).

### oclp-amd-gcn-chromium

**Open issue.** [AMD GCN GPUs and Chrome Rendering Issues](https://github.com/dortania/OpenCore-Legacy-Patcher/issues/1145). D500 hardware is explicitly included. The report concerns severe application UI rendering corruption, freezing, or unusable Electron UI.

Scope: OS: Ventura or newer, as stated in the issue. Software: Chrome 125+; some Electron applications. Hardware: MacPro6,1 FirePro D300/D500/D700; AMD HD 7000; MacBookPro11,5 R9 M370X.

Limits: Behavior on individual Tahoe builds and current application versions is not established. The issue does not identify transient whole-screen wake artifacts as its signature.

Read-only follow-up: Record whether corruption is confined to a Chromium/Electron window or affects the entire display. Read only an explicitly selected application's bundle version if application matching is added. Correlate existing timestamps without assuming causation.

### oclp-legacy-metal-limitations

**Open tracker; resolved rows excluded.** [Legacy Metal Graphics Support and macOS Ventura - Sequoia](https://github.com/dortania/OpenCore-Legacy-Patcher/issues/1008). The tracker lists Haswell/Kepler functional limitations and graphics artifacts. Resolved rows are explicitly crossed out and must not be converted into current warnings.

Scope: OS: Ventura; Sonoma; Sequoia; per-item scope differs. Hardware: Intel Haswell; NVIDIA Kepler; AMD GCN 1-3 including FirePro D500.

Limits: The issue title and tables do not validate these individual limitations on Tahoe. A detected GPU family does not prove any listed symptom is present.

Read-only follow-up: Read both GPUs rather than selecting only the first device. Match the exact application feature, OS family, and symptom before surfacing a row. Keep closed/resolved and unresolved limitations separate.

### oclp-update-root-patch-dependencies

**Official preparation guidance.** [Updating and post-install patch package requirements](https://dortania.github.io/OpenCore-Legacy-Patcher/POST-INSTALL.html#packages-requiring-networking). GCN root patching requires a KDK. Haswell/Kepler need MetallibSupportPkg matched to the OS build. Updates can remove root patches; app, EFI and root-patch versions are separate evidence.

Scope: OS: AMD GCN: Ventura or newer; Haswell/Kepler MetallibSupportPkg: Sequoia or newer. Hardware: MacPro6,1 FirePro D500; Haswell and NVIDIA Kepler systems.

Limits: An installed dependency does not establish that current root patches are applied or valid. Exact host package compatibility has not been checked.

Read-only follow-up: Compare running OS build with whitelisted patch metadata. Report patcher version/date and package evidence without declaring validity. Keep a missing dependency separate from a proven runtime fault. For a patching failure, preserve its sanitized explicit error and consult the official matching-package guidance.

Additional sources: [MetallibSupportPkg](https://dortania.github.io/OpenCore-Legacy-Patcher/POST-INSTALL.html#metallibsupportpkg), [KDK / Kernel Debug Kit](https://dortania.github.io/OpenCore-Legacy-Patcher/POST-INSTALL.html#kdk-kernel-debug-kit), [Updating](https://dortania.github.io/OpenCore-Legacy-Patcher/UPDATE.html).

### oclp-mbp113-gmux-boot

**Closed historical issue; Monterey guidance remains.** [MacBookPro11,3 GMUX issues with 12.0 Beta 7 and newer](https://github.com/dortania/OpenCore-Legacy-Patcher/issues/522). When Kepler drivers are unavailable, the documented GMUX display handoff can fail during boot.

Scope: OS: Monterey 12.0 beta 7 and later Monterey guidance. OCLP: Kepler acceleration restoration introduced in 0.2.5. Hardware: MacBookPro11,3 with Haswell iGPU and NVIDIA Kepler dGPU.

Limits: No exact Tahoe behavior established by this historical issue. Boot black screen is distinct from a short wake artifact.

Read-only follow-up: Confirm model and both GPU identities. Read existing patch/OS evidence and distinguish boot from wake timing.

Additional sources: [Black Screen on MacBookPro11,3 in macOS Monterey](https://dortania.github.io/OpenCore-Legacy-Patcher/TROUBLESHOOT-MISC.html#black-screen-on-macbookpro11-3-in-macos-monterey).

### oclp-sleep-wake-scope-guard

**Open historical issue; unrelated TeraScale guidance excluded.** [Hibernation Issues with OpenCore](https://github.com/dortania/OpenCore-Legacy-Patcher/issues/72). Hibernation failure and display corruption require different symptom matching. Do not apply the older TeraScale wake workaround to the Mac Pro.

Scope: OS: Historical Big Sur/Monterey hibernation discussion; exact full issue scope unspecified; Separate distortion guidance: macOS 11.3 through Monterey. Hardware: Issue #72: some legacy Macs; authoritative body does not enumerate affected models; Separate distortion guidance: TeraScale 1 HD2000-4000.

Limits: No reviewed source confirms MacPro6,1 D500 + Tahoe transient wake corruption. The TeraScale 1 distortion guidance does not apply to FirePro D500 GCN or Haswell/Kepler.

Read-only follow-up: Use existing bounded pmset/unified logs and embedded-timestamp diagnostic reports. Separate Sleep, Wake, DarkWake, hibernation-related entries and explicit failure signatures. Preserve timezone and distinguish correlation from cause.

Additional sources: [TeraScale 1 wake distortion scope](https://dortania.github.io/OpenCore-Legacy-Patcher/TROUBLESHOOT-HARDWARE.html#wake-from-sleep-heavily-distorted-on-ati-amd-terascale-1-from-macos-11-3-to-monterey).

### oclp-tahoe-filevault-restored

**Release guidance; support restored in the Tahoe RC.** [FileVault 2 support restored in the Tahoe release candidate](https://github.com/dortania/OpenCore-Legacy-Patcher/releases/tag/3.0.0-rc.2). The current release notes restore Tahoe FileVault 2 support; a blanket Tahoe/FileVault incompatibility rule is stale.

Scope: OS: macOS 26. OCLP: 3.0.0-rc.2 release notes. Hardware: No model-specific validation matrix supplied by the cited release.

Limits: Host encryption status does not establish boot/recovery readiness. An app reporting 3.0.0 is not sufficient to identify its release candidate.

Read-only follow-up: Read fdesetup status and report enabled/disabled/unknown. Show installed and booted OCLP evidence separately.

Additional sources: [Tahoe support tracker](https://github.com/dortania/OpenCore-Legacy-Patcher/issues/1167).

### oclp-modern-wireless-scope

**Official detection and release guidance.** [Modern Wireless detection and Tahoe wireless improvements](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/patchsets/hardware/networking/modern_wireless.py). Wireless applicability should follow detected chipset and OS. Current RC notes describe improved wireless patches, so old blanket Tahoe Wi-Fi failure claims are stale.

Scope: OS: Sonoma and newer for this patch family. Hardware: Detected Broadcom AirPortBrcm4360 or AirportBrcmNIC chipset; source also handles a third-party variant without official support.

Limits: Model alone does not establish the installed wireless adapter. This source alone does not establish a connection failure or compatibility with every Tahoe build.

Read-only follow-up: Read only adapter/chipset presence and sanitized patch-set names. Do not export SSID, BSSID, MAC address, neighboring networks or connection credentials.

Additional sources: [3.0.0-rc.2 wireless improvements](https://github.com/dortania/OpenCore-Legacy-Patcher/releases/tag/3.0.0-rc.2).

### opencore-nvme-hibernation-path

**Fixed in OpenCore 1.0.8; affected range not established.** [NVMe Mac hibernation device-path repair](https://github.com/acidanthera/OpenCorePkg/releases/tag/1.0.8). OpenCore 1.0.8 repairs an unresolved ATAPI device-path case during hibernation on NVMe Macs.

Scope: Hardware: Genuine Macs with NVMe storage. OpenCore: Fix shipped in 1.0.8. OS: Specific macOS versions not stated in release note.

Limits: The host storage protocol and affected hibernation device path are not collected. No universal affected version range was established.

Read-only follow-up: Review existing storage protocol and power/boot evidence. Inspect hibernation handling in a supplied EFI configuration copy.

Additional sources: [ATAPI hibernation path repair](https://github.com/acidanthera/OpenCorePkg/commit/fa14f4f), [Official 1.0.8 release workflow](https://github.com/acidanthera/OpenCorePkg/actions/runs/36352833721).

### opencore-dmg-secureboot-restore

**Merged fix; shipped in OpenCore 1.0.8.** [Apple Secure Boot restoration after DMG loading](https://github.com/acidanthera/OpenCorePkg/pull/610). The merged fix restores verification availability after DMG loading; release 1.0.8 contains it.

Scope: Software: Apple Secure Boot verification after DMG loading. Hardware: PR reports an installer crash example on unsupported T2 Macs. OS: macOS 26 installer for the reported T2 crash example.

Limits: Host SecureBootModel/DmgLoading and DMG boot evidence are unknown. MacPro6,1 is outside the T2 crash example. SIP, authenticated-root and FileVault status do not determine OpenCore Apple Secure Boot policy.

Read-only follow-up: Inspect SecureBootModel and DmgLoading in a supplied configuration copy. Review existing installer/recovery boot evidence and OCLP configuration requirements.

Additional sources: [1.0.8 release](https://github.com/acidanthera/OpenCorePkg/releases/tag/1.0.8), [Apple Secure Boot policy and sealed-volume limits](https://github.com/acidanthera/OpenCorePkg/blob/1.0.6/Docs/Configuration.tex#L4192-L4255).

### opencore-tahoe-xhciportlimit

**Compatibility improvement released in OpenCore 1.0.7.** [Tahoe compatibility improvement for XhciPortLimit](https://github.com/acidanthera/OpenCorePkg/releases/tag/1.0.7). Release 1.0.7 improves Tahoe compatibility of the XhciPortLimit quirk.

Scope: OS: macOS Tahoe 26. Configuration: Kernel/Quirks/XhciPortLimit. OpenCore: Compatibility improvement in 1.0.7.

Limits: Host XhciPortLimit setting is uncollected. Display USB errors near wake do not establish a port-limit problem.

Read-only follow-up: Inspect the quirk value in a supplied configuration copy. Compare existing USB enumeration and error records; review OCLP-supported component versions.

### opencore-gpu-firmware-boot-2126

**Open historical issue; Ventura boot scope.** [Ventura boot issues with certain GPU and firmware combinations](https://github.com/acidanthera/bugtracker/issues/2126). The issue describes early boot stalls around PCI initialization for particular GPU/firmware combinations.

Scope: OS: Ventura beta 1 through beta 8 in original report; later Ventura user reports. Hardware: Genuine MacPro6,1 with dual D300 in original report; MacPro6,1 with D500 in a later individual user report.

Limits: No confirmed Tahoe scope or universal fixed release is established. The D500 comment is an individual report, not confirmation for all D500 machines.

Read-only follow-up: Compare an existing boot failure capture with the issue OS, GPU and boot stage.

### opencore-emulated-nvram-wake-2134

**Closed historical issue; fixed in OpenCore 0.8.6.** [Historical wake hang with standalone emulated NVRAM on real Macs](https://github.com/acidanthera/bugtracker/issues/2134). The closed driver-specific wake report has a documented 0.8.6 fix.

Scope: Hardware: EFI 1.1 systems including earlier real Macs. Configuration: Standalone OpenVariableRuntimeDxe.efi emulated NVRAM driver.

Limits: The host driver presence/version and EFI 1.1 applicability are uncollected. OpenCore version does not establish every installed standalone driver version.

Read-only follow-up: Inspect enabled driver names and provenance in a supplied EFI copy if a matching hang is independently observed.

Additional sources: [0.8.6 wake fix](https://github.com/acidanthera/OpenCorePkg/releases/tag/0.8.6).

### opencore-config-picker-version

**Version-specific validation guidance.** [Match picker/configuration validation to the booted OpenCore version](https://github.com/acidanthera/OpenCorePkg/blob/1.0.6/Utilities/ocvalidate/README.md). Use the matching validator version. The 1.0.6 checker requires External PickerMode when OpenCanopy is enabled; a clean result is not comprehensive validation.

Scope: OpenCore: Validation rules verified for 1.0.6. Configuration: OpenCanopy.efi and Misc/Boot/PickerMode.

Limits: No active EFI configuration or mixed-component defect has been observed. A supplied EFI copy is not automatically the booted copy.

Read-only follow-up: Check ocvalidate --version and run the matching validator against a local copy. Inspect existing picker driver/resource files without modifying them.

Additional sources: [OpenCanopy and PickerMode consistency check](https://github.com/acidanthera/OpenCorePkg/blob/1.0.6/Utilities/ocvalidate/ValidateMisc.c#L246-L264), [Validation limitations](https://github.com/acidanthera/OpenCorePkg/blob/1.0.6/Docs/Configuration.tex#L373-L376).

### opencore-oem-identity-evidence

**Official identity interpretation guidance.** [Separate preserved OEM identity evidence from the exposed model](https://github.com/acidanthera/OpenCorePkg/blob/1.0.6/Docs/Configuration.tex#L4054-L4085). Compare valid OS-exposed and preserved OEM identifiers while retaining provenance and persistence limits.

Scope: Configuration: ExposeSensitiveData bit 0x08; oem-product SMBIOS Type 1 ProductName; ForceOcWriteFlash.

Limits: Preserved firmware values are not authenticated factory identity. Absence cannot establish spoofing or absence of OpenCore.

Read-only follow-up: Read only the allowlisted oem-product variable and OS model; retain exact source labels.

Additional sources: [ForceOcWriteFlash persistence](https://github.com/acidanthera/OpenCorePkg/blob/1.0.6/Docs/Configuration.tex#L8361-L8365).

## Review maintenance

Re-review source status and exact scope before changing matching rules. Retain resolved entries as history where useful. Add a new automatic finding only when available evidence supports its specific prerequisites; otherwise keep it as reference or an evidence gap. Do not imply that these 15 records cover every OpenCore/OCLP problem or that a clean report certifies a healthy installation.
