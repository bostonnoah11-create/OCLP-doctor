# Contributing to OCLP Doctor

Thank you for helping improve this read-only diagnostic tool. Useful contributions include reproducible bug reports, clearer documentation, synthetic parser fixtures, and validation on additional Intel Macs and macOS versions.

OCLP Doctor is independent of Dortania and the official OCLP project. Use this repository for OCLP Doctor behavior and proposals; its findings are observations, not confirmed hardware diagnoses.

## Report a bug

Search existing issues, then use the bug-report form. Include:

- OCLP Doctor version/build or source commit.
- macOS version/build and the model identifier, such as `MacPro6,1`. A model identifier is sufficient; do not include a device serial number or UUID.
- Whether you used real collection or a named synthetic demo.
- The affected page, short reproduction steps, expected behavior, and actual behavior.
- A short, sanitized summary of the relevant item status or collection coverage, if needed.

Only include OCLP/OpenCore versions when relevant and known. Distinguish an installed app version from boot evidence rather than guessing.

## Keep public reports private-data free

Issues and pull requests are public. Do not paste or attach raw logs, full text/JSON reports, crash reports, sysdiagnose archives, EFI configurations, NVRAM dumps, or other private files. Do not include serial numbers, UUIDs, usernames, home paths, device names, addresses, account details, or credentials. Avoid screenshots that expose these details.

Describe the symptom and relevant status in your own words. If exact data structure is needed, replace it with a small synthetic example that preserves the behavior. Use relative timing such as “two seconds after wake” when an exact personal timestamp is unnecessary. Review every field before submitting; the app's best-effort redaction does not make a complete report safe to post.

The app does not submit issues automatically. Sharing any summary remains your explicit action. If you cannot describe a potential security or privacy problem without disclosing sensitive information, do not post the sensitive material in a public issue; ask for a suitable reporting route without including it.

## Propose a feature

Use the feature-request form to explain the problem, the proposed behavior, and how someone could verify the result. Read-only diagnostics are the current scope. A new collector should identify a verifiable source and explain unavailable or ambiguous results.

## Develop and validate

See the [README requirements](README.md#requirements) for build and runtime details. The app targets Intel macOS 12+, while the current build requires the macOS 26 SDK and the verified automated-test runtime requires macOS 14+.

```sh
bash Scripts/test.sh
bash Scripts/build-app.sh
```

The app is packaged with an ad-hoc signature for local testing. Developer ID signing and notarization are not part of these scripts. Build output and caches are ignored by Git; do not commit them.

For UI work, use the synthetic demos in the README. After building, run `bash Scripts/verify-window-layout.sh` from a logged-in macOS session when changing layout. The geometry verifier exercises its own demo window; it does not replace manual appearance, keyboard, accessibility, or full-screen testing.

## Submit a pull request

Keep the change focused. Explain the problem, resulting behavior, relevant verification, and any remaining limitations. Add meaningful tests for changes to parsing, classification, collection limits, or privacy behavior. Use synthetic fixtures rather than captured personal logs.

Preserve these project conventions:

- Collect evidence without changing the system or requesting administrator access.
- Keep commands bounded and their sources visible; represent missing data as Unknown.
- Distinguish raw log levels, observations, and inferred interpretations. Do not turn absence of evidence into a health guarantee.
- Keep UI text in English, retain macOS 12-compatible fallbacks, and support resizable windows and accessibility settings.
- Cite primary sources when updating the offline issue catalog, with a review date and explicit scope.

Do not commit generated reports, credentials, local build products, or private fixtures. Contributions are made under the project's [MIT License](LICENSE).
