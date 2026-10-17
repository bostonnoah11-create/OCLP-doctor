# Validation record

Public release preparation: 2026-10-18 (Asia/Seoul). App version 0.5.1.

## Automated diagnostic tests

The 0.5.0 diagnostic engine passed **173 tests across 13 Swift Testing suites**. Coverage includes bounded process execution, parsing and privacy filtering, missing/partial evidence, model identity, reported Metal families, memory slots and ECC observations, focused wake intervals, Bluetooth lifecycle interpretation, counting before display sampling, report encoding, and official-issue prioritization.

The subsequent 0.5.1 layout change did not change diagnostic collection behavior. Public-source preparation generalizes host-specific wording in the offline catalog and adds repository documentation and CI. **All 173 tests in 13 suites passed again on the final public source on 2026-10-18.**

## Windowed navigation

**126 navigation checks passed** for seven pages in forward and reverse order, three synthetic configurations (MacPro6,1, MacBookPro11,3, unavailable evidence), and three usable content sizes: 1040 × 720, 1200 × 800, and 1360 × 880.

Window frame, content rectangle, minimum sizes, sidebar, header, and scroll viewport remained stable within one backing pixel during navigation. Deliberate resizing was accepted. All three fixture runs ended with `WINDOW_LAYOUT_PASS` and empty stderr.

`Scripts/verify-window-layout.sh` reproduces these checks in a logged-in macOS session. It launches only explicitly selected synthetic demos, adjusts its own test window, reads geometry, and exits. Normal app navigation never sets the window frame. Geometry checks do not replace manual appearance, keyboard, accessibility, or full-screen transition testing.

## Collection and packaging checks

A normal-user collection on an Intel Mac completed all focused latest-wake segments: power/graphics, Bluetooth lifecycle, and three independent HCI intervals. Broader history remained Partial under dense logging. Completed selected queries do not guarantee complete macOS retention, successful device recovery, or a cause for a symptom. Repeated log records are not unique incidents; history and focused counts overlap.

Final public beta **0.5.1 (build 10)** packaging, property-list validation, Intel architecture verification, and strict ad-hoc signature verification passed. The app deployment target is macOS 12.0 / x86_64. Local builds used Swift 6.3.3 with macOS SDK 26.5. Distribution packaging strips debug-map records containing local build paths before signing and includes LICENSE and NOTICE. A final binary scan found no development username or workspace-path occurrences. The minimal SVG icon was inspected at 1024 and 64 pixels and packaged into an ICNS.

The CI workflow selects an Intel hosted runner and Xcode 26.3, runs synthetic tests, builds the app, and verifies architecture, minimum OS metadata, and ad-hoc signing. It does not run host diagnostics or GUI checks. A workflow definition is not evidence of a successful GitHub run; check the repository Actions results.

## Remaining limits

- A physical MacBookPro11,3 and macOS 12–15 runtimes have not been validated. Synthetic model fixtures do not establish physical compatibility.
- Functional graphics acceleration, RAM stress testing, hardware fault diagnosis, root-patch validity, and actual sleep/wake recovery are outside these checks.
- Complete history retrieval is not guaranteed. Timeouts, output limits, unrecognized input, and missing sources stay visible.
- Manual copy/refresh, full-screen transitions, and comprehensive accessibility and appearance testing remain incomplete.
- The app is ad-hoc signed for beta testing, without Developer ID signing or notarization.
- Public artifacts exclude development-machine logs, full diagnostic reports, identifiers, and detailed security configuration.

These checks establish only the behavior and coverage described here, not overall Mac health or universal compatibility.
