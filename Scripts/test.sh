#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${OCLP_DOCTOR_BUILD_ROOT:-$PROJECT_ROOT/.build}"
DEVELOPER_ROOT="$(xcode-select -p)"
mkdir -p "$BUILD_ROOT/module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/module-cache"

TEST_ARGS=(--disable-xctest --enable-swift-testing --package-path "$PROJECT_ROOT"
  --scratch-path "$BUILD_ROOT" --cache-path "$BUILD_ROOT/cache"
  --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security"
  --manifest-cache local --disable-sandbox)

# Some Command Line Tools distributions bundle Swift Testing outside SwiftPM's
# automatic framework search paths. Use those bundled libraries, without downloads.
TEST_FRAMEWORKS="$DEVELOPER_ROOT/Library/Developer/Frameworks"
TEST_INTEROP="$DEVELOPER_ROOT/Library/Developer/usr/lib"
TEST_MACROS="$DEVELOPER_ROOT/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -d "$TEST_FRAMEWORKS/Testing.framework" ]; then
  TEST_ARGS+=(-Xswiftc -F -Xswiftc "$TEST_FRAMEWORKS"
    -Xlinker -F -Xlinker "$TEST_FRAMEWORKS"
    -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS")
  if [ -f "$TEST_MACROS" ]; then
    TEST_ARGS+=(-Xswiftc -load-plugin-library -Xswiftc "$TEST_MACROS")
  fi
  if [ -f "$TEST_INTEROP/lib_TestingInterop.dylib" ]; then
    TEST_ARGS+=(-Xlinker -rpath -Xlinker "$TEST_INTEROP")
  fi
fi
swift test "${TEST_ARGS[@]}" "$@"
