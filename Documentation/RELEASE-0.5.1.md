# OCLP Doctor 0.5.1 — initial public prerelease

OCLP Doctor is an independent, unofficial diagnostic app for older Intel Macs
using OpenCore Legacy Patcher. This first public prerelease provides read-only
observations and evidence; it does not install patches or perform repairs.

- Overview presents recorded problems, compatibility references, and evidence
  gaps before general information. Hardware, boot/security, patch evidence, and
  an offline catalog of 15 official OpenCore/OCLP references are available on
  separate pages.
- Sleep & Wake prioritizes the latest full wake with independent power/graphics,
  Bluetooth lifecycle, and bounded HCI queries. Focused counts include collected
  matches before display sampling; timeouts, missing sources, and coverage limits
  remain visible. Repeated log records are not distinct incidents.
- Bluetooth evidence distinguishes explicit failures and exit/start records from
  an observed change of daemon process. A process change does not establish an
  exact restart time, cause, or recovery. Unrelated WIPROX startup records are
  excluded.
- Navigation stays within the existing window size. **126 windowed layout checks
  passed**, covering seven pages in both directions, three sizes, and three
  synthetic fixtures on the validation host. This does not replace manual
  interaction, accessibility, or older-OS testing.

The app targets **Intel x86_64 and macOS 12 or later**. Runtime checks on macOS
12–15 and a physical MacBookPro11,3 remain outstanding; the deployment target
does not establish compatibility on every release. Building requires the macOS
26 SDK and its matching Swift toolchain. Big Sur and native Apple Silicon are
outside the current app target.

The local app package is **ad-hoc signed**, without Developer ID signing or
notarization. It is a beta for evaluation, with no automatic recovery actions,
administrator authentication, settings changes, or background network requests.
No personal diagnostic logs accompany this release. Review any report before
choosing to share it.

See [README.md](../README.md) for build instructions and
[VALIDATION.md](VALIDATION.md) for verification scope and remaining checks.
