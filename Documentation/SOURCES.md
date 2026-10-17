# Phase 1 diagnostic sources

Reviewed on 2026-10-17. The following are official Dortania and Acidanthera sources and documentation. The `main` and `master` branches may change. The app does not consult the internet to determine the latest version or compatibility.

## Distinguishing app, EFI, and root patch versions

- [OCLP package.py](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/ci_tooling/build_modules/package.py): The standard app location is `/Library/Application Support/Dortania/OpenCore-Patcher.app`. Installing the package alone does not install EFI or root patches.
- [OCLP package_scripts.py](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/ci_tooling/build_modules/package_scripts.py): Creates the `/Applications/OpenCore-Patcher.app` shortcut. Doctor checks only these two standard locations and deduplicates symlinks to the same app. It may miss apps installed elsewhere.
- [OCLP OpenCore-Patcher-GUI.spec](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/OpenCore-Patcher-GUI.spec): The bundle ID is `com.dortania.opencore-legacy-patcher`; the patcher version is placed in `CFBundleShortVersionString` and `CFBundleVersion`.
- [OCLP EFI build.py](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/efi_builder/build.py): `OCLP-Version` identifies the OCLP version used to create the EFI configuration. It is not assumed to match the installed app version.

## Reading NVRAM

- [OCLP device_probe.py](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/detections/device_probe.py): Official implementation reading `OCLP-Version`, `OCLP-Model`, `opencore-version`, and `boot-path` under GUID `4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102`. Doctor queries only the version and setting keys it needs, not all NVRAM.
- [OpenCore Configuration.tex](https://github.com/acidanthera/OpenCorePkg/blob/master/Docs/Configuration.tex): `ExposeSensitiveData` bit `0x02` exposes the bootloader version in a UEFI variable. A hidden version may appear as `UNK-000-0000-00-00`. An unexposed or unreadable value does not establish that the Mac did not boot through OpenCore.
- [OCLP utilities.py](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/support/utilities.py): NVRAM strings may be Data or String values and require NUL cleanup and handling for invalid UTF-8. Doctor decodes percent-encoded bytes before parsing CLI output.
- [OCLP security.py](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/efi_builder/security.py): Configures `-allow_fv` and `-allow_amfi` in `OCLP-Settings` and `csr-active-config` under the Apple GUID. Doctor displays only recognized tokens and redacts unknown ones. These tokens do not represent all GUI settings.
- [OCLP FAQ](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/docs/FAQ.md): GUI settings are stored in a separate plist; applying them to EFI requires building and installing. Doctor does not modify that settings file.

## Root patch metadata

- [OCLP sys_patch.py](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/sys_patch.py): Writes `System/Library/CoreServices/OpenCore-Legacy-Patcher.plist` on the root volume.
- [OCLP sys_patch_helpers.py](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/sys_patch_helpers.py): Merges patcher version, time, OS, support package and path metadata with patch-set dictionaries at the top level. The leading part of `OS Version` is the Darwin major/minor version, not the macOS product version.
- [OCLP patchsets/base.py](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/patchsets/base.py): Internal operations include overwriting, merging, and deleting files and executing commands. Doctor neither executes these internal operations nor includes their paths and commands in reports.
- The conservative allowlist of displayed patch names is based on [Non-Metal](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/patchsets/shared_patches/non_metal.py), [Intel Ivy Bridge](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/patchsets/hardware/graphics/intel_ivy_bridge.py), [Nvidia Kepler](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/patchsets/hardware/graphics/nvidia_kepler.py), [Legacy Wireless](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/patchsets/hardware/networking/legacy_wireless.py), [Modern Wireless](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/patchsets/hardware/networking/modern_wireless.py), and [detection of earlier names](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/patchsets/detect.py). Other keys are counted without displaying their names. Omitting an unrecognized name does not establish that a patch is missing.

Doctor limits metadata reads to 1 MiB and displays only the patcher version, time, Darwin/build version, and recognized patch-set names. KDK/Metal paths, arbitrary URLs, commands, and user information are not exported. **Current root patch validity remains Unknown**, regardless of whether metadata is found. Missing, unreadable, oversized, and malformed files are distinguished.

Additional confirmed top-level names for the target GPUs are `Intel Haswell` from [Intel Haswell](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/patchsets/hardware/graphics/intel_haswell.py) and `AMD Legacy GCN` from [AMD Legacy GCN](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/patchsets/hardware/graphics/amd_legacy_gcn.py).

## SIP and interpretation limits

- [Official Post-Installation: SIP settings](https://dortania.github.io/OpenCore-Legacy-Patcher/POST-INSTALL.html#sip-settings): Root patches may require reduced SIP protection appropriate to the model and OS. Enabling SIP after root patching may damage the installation. Doctor provides no enable, disable, or recovery action.
- [Official Post-Installation: Applying Post Install Volume Patches](https://dortania.github.io/OpenCore-Legacy-Patcher/POST-INSTALL.html#applying-post-install-volume-patches): OS updates may remove patches, or networking patches may be applied before other patches. A record file does not prove that all drivers currently work correctly.

Doctor parses only recognized status phrases from `csrutil status`, `csrutil authenticated-root status`, and `fdesetup status`. Failures, insufficient permissions, and unsupported output remain Unknown. The NVRAM CSR value is a four-byte little-endian observation, not a substitute for all running security policies. Boot arguments are redacted unless they match reviewed flags or exact numeric settings; unrecognized key names are also withheld.

## Sleep and wake evidence scope

The Sleep & Wake extension is intended to present local evidence from the last seven days. The final collector's source commands and parser limits must be documented alongside its verification. Historical events alone do not establish the cause of a failure, current graphics acceleration, or a successful return to an interactive desktop. Collection must not alter power settings, initiate sleep, restart the Mac, escalate privileges, or transmit logs.


## Reported and preserved model identity

[OCLP device_probe.smbios_probe](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/detections/device_probe.py) distinguishes the OS-reported `model` from `oem-product` under GUID `4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102`. Its [utilities.get_nvram](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/support/utilities.py) reads the GUID-qualified property in `IODeviceTree:/options` and decodes Data/String values. Doctor reuses its fixed, read-only NVRAM command path to read only this key.

[OpenCore Configuration](https://github.com/acidanthera/OpenCorePkg/blob/master/Docs/Configuration.tex) documents `ExposeSensitiveData` bit `0x08`, which exposes original SMBIOS vendor information, including the Type 1 ProductName in `oem-product`. [OpenCorePlatform.c](https://github.com/acidanthera/OpenCorePkg/blob/master/Library/OcMainLib/OpenCorePlatform.c) and [SmbiosPatch.c](https://github.com/acidanthera/OpenCorePkg/blob/master/Library/OcSmbiosLib/SmbiosPatch.c) show extraction before patching and variable publication. The variables use volatile BS/RT attributes by default, but `ForceOcWriteFlash` can persist the values. The preserved value can therefore be missing, custom, or stale; it is not authenticated physical identity.

The Overview suffix `(spoofed)` indicates a valid reported/preserved model mismatch. A missing original value is Unknown, even if OpenCore is installed. `OCLP-Model` identifies the build model and is not used as original-model evidence. A board-only change is also not a model-identifier mismatch. These checks never modify NVRAM, exposure settings, SMBIOS, or EFI.

## Reported Metal family and RAM/ECC fields (Beta 0.4.0)

Field names and labels were checked against Apple-supplied System Information data and installed resources. The [Apple System Information guide](https://support.apple.com/guide/system-information/system-information-syspr35536/mac) describes hardware/software reports; their full output can include identifying data, so Doctor extracts only selected fields.

`SPDisplaysDataType` can report `spdisplays_mtlgpufamilysupport = spdisplays_metal2`. The installed `/System/Library/SystemProfiler/SPDisplaysReporter.spreporter/Contents/Resources/Localizable.loctable` identifies Metal 2/3/4 labels. Doctor supports this field and established alternate field names, while retaining the exact source field in evidence. This is reported Metal information, not an acceleration or stability test.

`SPMemoryDataType` supplies a top-level `global_ecc_state` and slot records in `_items`. The installed `/System/Library/SystemProfiler/SPMemoryReporter.spreporter/Contents/Resources/Localizable.loctable` identifies `dimm_status` values `ok`, `empty`, `mapped_out`, `ecc_errors` and labels `dimm_ecc_errors` as ECC Correctable Errors. Doctor also validates `_name`, `dimm_size`, `dimm_type` and `dimm_speed`. Unknown shapes and values remain Unknown. Boolean, fractional, negative and overflowing error counts are rejected.

Correctable-error counters may be absent and remain Unknown. The app does not infer ECC mode from the model or memory-type label, or infer zero errors from an absent count. Positive explicit correctable counts and mapped-out/error statuses warrant review, while a zero count or OK status does not establish memory health. Counter reset periods, live rates, uncorrectable-error coverage and memory stress testing remain outside scope. Serial, part and manufacturer values are excluded from exported memory data.
