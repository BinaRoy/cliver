#!/usr/bin/env bash
# Build Clive and run the full test suite using Cangjie envsetup.sh.
# This script sources the given envsetup so cjc and cjpm are on PATH and
# the toolchain can find the runtime.
#
# Usage:
#   ./scripts/build_and_test_with_envsetup.sh
#   CANGJIE_ENVSETUP=/path/to/envsetup.sh ./scripts/build_and_test_with_envsetup.sh
#
# Default envsetup (if CANGJIE_ENVSETUP is not set):
#   /Users/danghica/cangjie/envsetup.sh

set -e
cd "$(dirname "$0")/.."

CANGJIE_ENVSETUP="${CANGJIE_ENVSETUP:-/Users/danghica/cangjie/envsetup.sh}"

if [ ! -f "${CANGJIE_ENVSETUP}" ]; then
  echo "Error: envsetup not found: ${CANGJIE_ENVSETUP}"
  echo "Set CANGJIE_ENVSETUP to the path of your cangjie/envsetup.sh"
  exit 1
fi

echo "=== Sourcing Cangjie environment: ${CANGJIE_ENVSETUP} ==="
# shellcheck source=/dev/null
source "${CANGJIE_ENVSETUP}"

if ! command -v cjpm >/dev/null 2>&1; then
  echo "Error: cjpm not found after sourcing envsetup. Check that envsetup.sh adds cjpm to PATH."
  exit 127
fi
if ! command -v cjc >/dev/null 2>&1; then
  echo "Error: cjc not found after sourcing envsetup. Check that envsetup.sh adds cjc to PATH."
  exit 127
fi

echo "Using cjpm: $(which cjpm)"
echo "Using cjc: $(which cjc)"
echo ""

# Remove cjpm dependency cache so a new scan matches this toolchain (avoids DataModelException
# when cache was produced by a different cjc/cjpm version).
rm -f target/.dep-cache sample_cangjie_package/target/.dep-cache 2>/dev/null || true

./scripts/build_and_test.sh
