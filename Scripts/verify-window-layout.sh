#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$PROJECT_ROOT/dist/OCLP Doctor.app}"
RESULTS="${OCLP_DOCTOR_BUILD_ROOT:-$PROJECT_ROOT/.build}/layout-checks"
mkdir -p "$RESULTS"
RESULTS="$(cd "$RESULTS" && pwd)"
if [ ! -d "$APP" ]; then
  printf 'Build the app first. App bundle missing: %s\n' "$APP" >&2
  exit 1
fi

# Explicit demo launches only. The app moves/resizes its own verification window,
# cycles every page, records geometry, and exits. No real diagnostics are collected.
for FIXTURE in mac-pro macbook-pro unavailable; do
  OUT="$RESULTS/$FIXTURE.out"
  ERR="$RESULTS/$FIXTURE.err"
  : > "$OUT"
  : > "$ERR"
  /usr/bin/open -W -n --stdout "$OUT" --stderr "$ERR" "$APP" --args \
    --verify-window-layout "--demo-$FIXTURE"
  if [ -s "$ERR" ] || /usr/bin/grep -q '^WINDOW_LAYOUT_FAIL ' "$OUT" || ! /usr/bin/grep -q '^WINDOW_LAYOUT_PASS ' "$OUT"; then
    printf 'Window layout verification failed: %s\nLogs: %s\n' "$FIXTURE" "$RESULTS" >&2
    exit 1
  fi
  /usr/bin/grep '^WINDOW_LAYOUT_PASS ' "$OUT"
done
printf 'Window layout logs: %s\n' "$RESULTS"
