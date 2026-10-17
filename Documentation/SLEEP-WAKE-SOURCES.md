# Sleep / Wake evidence sources

Reviewed 2026-10-17. This feature reads existing evidence. It never forces sleep/wake, changes pmset, modifies SIP, enables debug boot arguments, or changes logging settings.

## Explicit failures

[Apple's XNU IOPMrootDomain.cpp](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IOPMrootDomain.cpp) contains these diagnostic signatures:

- `Sleep Wake failure in EFI` in `saveFailureData2File`.
- `Sleep transition timed out` and `Wake transition timed out` in the watchdog failure description.
- `Sleep/Wake hang detected` in `sleepWakeDebugTrig`.

Only those explicit signatures create diagnostic-report failure events. A graphics-related error, ordinary wake, missing report, or a user's transient display symptom alone does not establish any of these failures or their cause. [Dortania's power-management guide](https://github.com/dortania/OpenCore-Post-Install/blob/master/universal/pm.md) also documents the EFI sleep/wake failure signature; its hardware/configuration suggestions are not automatically applied to genuine Macs.

## Diagnostic report collection and dates

The reader examines only top-level files in `/Library/Logs/DiagnosticReports` and the current user's `Library/Logs/DiagnosticReports`. It excludes symlinks, nested folders and Retired. Candidate extensions are `.panic`, `.ips`, `.diag`, or filenames containing a sleep/wake marker. The newest 40 candidates are considered, with a 1 MiB file limit, an 8 MiB total limit, and a 10,000-entry enumeration limit. Modification time is only a candidate prefilter.

An event requires a timestamp inside its report with an explicit numeric timezone offset or `Z`. File creation/modification dates and dates embedded in filenames are never substituted for the incident time. For classic text, the reader accepts `Date/Time:` or `Date:`. For JSON/IPS it checks the report's `date`, `captureTime`, or `timestamp`, then the metadata header's `timestamp`. IPS metadata and report JSON objects are decoded separately. A reliable timestamp that is missing or malformed results in partial coverage, not an invented event date.

[Apple's IPS format documentation](https://developer.apple.com/documentation/xcode/interpreting-the-json-format-of-a-crash-report) describes the two JSON objects, `captureTime` as the crash time, and metadata `timestamp` as a report-tracking time. When only that header timestamp is available, it remains a report timestamp rather than a confirmed transition-failure instant. [Apple Console report documentation](https://support.apple.com/guide/console/reports-cnsl664be99a/1.1) identifies diagnostic report formats such as `.diag`.

An incident report timestamp is the time recorded by that report; it is not guaranteed to mark the first moment that hardware stopped responding. Nearby wake events establish temporal proximity only. Multiple sources can describe the same incident; counts are observations unless explicitly deduplicated elsewhere.

Only fixed failure titles, numeric timeout durations, and parsed dates are exported. Raw filenames, usernames, hardware identifiers, UUIDs, addresses, paths, stack traces and arbitrary message text are excluded. Report sources are fixed labels plus an index. No raw report is copied to an output artifact.

## pmset and unified logs

The host's Apple-supplied `pmset(1)` manual describes `pmset -g log` as sleep/wake and power-management event history. It has no documented history-window parameter; the collector must filter parsed timestamps and disclose collection limits. `-g history`/`historydetailed` can require debug boot arguments and are excluded. In actual host output, **Wake Requests is a different event column from Wake**. Split the timestamp and full event column at the multi-space boundary, not on the first word. [Dortania's wake-reason examples](https://dortania.github.io/OpenCore-Post-Install/usb/misc/instant-wake.html) include maintenance wakes, which must not be classified as failures solely because they occur during sleep.

The host's Apple-supplied `log(1)` manual documents `log show --style compact|json|ndjson`, `--last`, `--start`, `--end`, `--predicate`, `--timezone`, and `--info`. Info/debug messages are excluded by default; retention and privacy redaction can hide evidence even when retrieval succeeds. The predicate restricts kernel, powerd, WindowServer, relevant bluetoothd messages and launchd messages naming bluetoothd. Graphics and display peripheral records must also correlate with a recorded power event. Results are merged and same-source duplicate records are removed. Some environments deny unified-log access; the app reports that source as unavailable rather than collecting unrelated data or changing permissions.

## Focused wake and Bluetooth evidence

After `pmset` is parsed, the latest full Wake anchors a query from five minutes before through two minutes after it, clipped to the requested history and collection time. DarkWake does not replace the full Wake anchor. Independent focused queries run before the two-hour and seven-day queries: power/graphics/USB, Bluetooth lifecycle/readiness, and compact-format HCI slices. The HCI slice after Wake + 10 seconds runs first, followed by the pre-wake interval and the dense first ten seconds of wake. Each interval has its own coverage. A high-volume HCI burst therefore cannot consume the lifecycle query or prevent the later HCI interval from being requested. It has separate coverage and retained events, so broad-history truncation cannot erase the focused evidence. If there is no reliable Wake timestamp, no date window is invented.

Date arguments include an explicit `+0000` offset. The local Apple `log(1)` documentation distinguishes date filtering from `--timezone`, which controls output formatting. Relying on `--timezone UTC` with timezone-less start/end values can query the wrong local interval. The collector rounds the clipped start upward and end downward to whole seconds and reports those exact bounds; the original Wake timestamp is preserved. The runner accepts only finite whole-second dates and a positive interval no longer than 420 seconds, with fixed executable, arguments and predicate; an unbounded focused command cannot execute. The focused predicate omits Fault-only graphics completion noise, which remains available through the broad queries.

Bluetooth classification uses explicit HCI failure/error/timeout/disallowed-command wording; exact launchd service identity `com.apple.bluetoothd` plus exited/spawned/running records; and explicit controller-ready or completed-initialization records. Planned starts, routine HCI operations, similarly named daemons, benign zero-error statements and records outside a full-Wake neighborhood are excluded. Unrecognized Bluetooth records are not promoted into HCI diagnoses. Original source severity is preserved: a meaningful failure signature may have Info level, while a Fault level alone remains insufficient.

Bluetooth exports contain fixed descriptions, timestamps, levels and event kinds. Device names and arbitrary raw Bluetooth messages are excluded. NDJSON identity preserves distinct simultaneous records and deduplicates identical records across overlapping queries. Compact HCI timestamps have only millisecond precision: equal rows can be separate real records, so they are not collapsed by timestamp/message. Compact samples use opaque segment-and-row identities; contiguous half-open slice boundaries prevent counting the same boundary twice. No process identifier or arbitrary Bluetooth text is exported. A change between non-overlapping bluetoothd process-identity ranges is recorded separately as a different daemon process observed. This is evidence consistent with a restart, not an exact exit/start timestamp or cause. A message saying WIPROX started is not a bluetoothd-start record. The lifecycle sequence supports temporal observation only. An exit does not establish a crash; a start does not establish device reconnection; a controller-ready message does not validate Bluetooth function or display recovery.

A statement that no further HCI failure signature was found requires completed focused query coverage, independently of display sampling, and names the start/end of that observation. Same-timestamp failure/start records, including compact millisecond buckets overlapping a more precise lifecycle timestamp, have ambiguous order and prevent an absence-of-recurrence statement. Partial, timed-out or unavailable evidence cannot establish no recurrence. This is not continuous monitoring.

Error categories are mutually exclusive classifications of Error-level records (all recognized matches in the focused scan, retained samples in the wider history): HCI, transition signatures, iSight transfer stalls, USB exclusive-access conflicts, wake-reason permission errors, graphics and other errors. Info/Fault HCI signatures still appear in the focused sequence and attention findings. Focused and historical counts overlap and must not be added; no count represents a number of unique hardware failures.

[Apple's sleep/wake troubleshooting guide](https://support.apple.com/guide/mac-help/if-your-mac-sleeps-or-wakes-unexpectedly-mchlp2995/mac) describes multiple possible influences, including apps and connected devices. A collected error's wording and timestamp do not identify a root cause by themselves.

## Log levels and bounded retention

Error and Fault are kept separate. A Fault-level graphics trace that says an operation completed is not promoted to a failed transition. Benign negative statements and zero counters are filtered. Known NDJSON completion summaries are metadata, not malformed events. Sandbox denials mentioning an executable named sleep are unrelated to system sleep and are excluded. A failed sleep-type query is not a failed sleep/wake transition. Graphics and display peripheral records within two minutes of a sleep/wake anchor are associated by time only.

Power/history subprocesses retain up to 4 MiB of retrieved output and scan at most 32 MiB. Each compact HCI slice instead retains its bounded complete output up to 64 MiB with a 35-second deadline. Focused power/graphics uses 15 seconds; the separate lifecycle query uses 35 seconds and a 1 MiB output cap because even a query returning few records must scan the dense source interval. The lifecycle predicate excludes generic daemon-start text that can refer to unrelated services. pmset uses 20 seconds, historical unified logs 30 seconds. No timeout is silently converted to success. Commands run without a shell, administrator authentication, or interactive input.

A dense HCI scan stores compact timestamp/severity observations for analysis instead of constructing hundreds of thousands of full event objects. Full counts and recurrence analysis are computed before display sampling. The focused view and history each display at most 500 events, while the compact Bluetooth sequence displays at most 100 representatives. Sample omissions do not reduce completed focused query coverage; actual timeout, output truncation or malformed input does. Legacy snapshots without full-scan metadata retain the conservative incomplete interpretation when records were omitted. Counts describe observed log records, not independent failures.

Unified-log and power-history excerpts are limited to 600 characters and use best-effort filtering of paths, common identifier keys, URLs, addresses, and process identifiers. Unlike the fixed text exported from diagnostic reports, arbitrary log prose cannot be guaranteed anonymous; review copied reports before sharing.

## Coverage semantics

Available means the requested bounded source could be read. It is not a statement that sleep or resume was healthy. Missing/inaccessible directories, failed reads, malformed candidate reports, missing reliable incident timestamps, and size/count limits are separately counted and yield partial or unavailable coverage. No matching error is reported as absence of evidence, never proof of a successful or visually correct resume.

Timestamp parsers are reused within each synchronous scan, with separate formatter instances for each scan. They are never shared as mutable state across concurrent collections. The compact parser uses the fixed UTC command context and caches whole-second timestamps before adding milliseconds, avoiding repeated formatter setup for a dense burst. This reduces high-volume log parsing overhead without weakening timezone requirements.
