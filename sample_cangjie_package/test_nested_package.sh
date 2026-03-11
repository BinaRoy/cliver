#!/usr/bin/env bash
# Test that commands from nested package directories are discovered and work.
# Uses src/demo_sub/demo_sub.cj (demo_sub/demo → David, Eugen, Flora) and
# src/demo_sub/nested/nested.cj (demo_sub/nested/demo → George, Hamid, Ilias).
# If the generated driver does not yet include nested discovery, the test is skipped.
#
# Usage: run from sample_cangjie_package (after cjpm build).
#   ./test_nested_package.sh
#   BUILD=1 ./test_nested_package.sh
# Optional: CANGJIE_ENVSETUP=/path/to/envsetup.sh

set -e
cd "$(dirname "$0")"

if [ -n "${CANGJIE_ENVSETUP}" ]; then
  # shellcheck source=/dev/null
  . "${CANGJIE_ENVSETUP}" 2>/dev/null || true
fi

if [ "${BUILD:-0}" = "1" ]; then
  cjpm build
fi

DRIVER="${PWD}/src/cli_driver.cj"
if [ ! -f "$DRIVER" ]; then
  echo "SKIP: nested package test (no generated cli_driver.cj; run Clive first)"
  exit 0
fi

if ! grep -q 'demo_sub/nested' "$DRIVER"; then
  echo "SKIP: nested package test (generated driver has no demo_sub/nested; nested discovery not yet used)"
  exit 0
fi

echo "=== Nested package tests (demo_sub/demo, demo_sub/nested/demo) ==="

# Run demo_sub/demo (David, Eugen, Flora)
out=$(cjpm run -- demo_sub/demo 2>/dev/null) || true
if ! echo "$out" | grep -q "David"; then
  echo "FAIL: demo_sub/demo output should contain 'David'. Got: $out"
  exit 1
fi
if ! echo "$out" | grep -q "Eugen"; then
  echo "FAIL: demo_sub/demo output should contain 'Eugen'. Got: $out"
  exit 1
fi
if ! echo "$out" | grep -q "Flora"; then
  echo "FAIL: demo_sub/demo output should contain 'Flora'. Got: $out"
  exit 1
fi
echo "PASS: demo_sub/demo (David, Eugen, Flora)"

# Run demo_sub/nested/demo (George, Hamid, Ilias)
out=$(cjpm run -- demo_sub/nested/demo 2>/dev/null) || true
if ! echo "$out" | grep -q "George"; then
  echo "FAIL: demo_sub/nested/demo output should contain 'George'. Got: $out"
  exit 1
fi
if ! echo "$out" | grep -q "Hamid"; then
  echo "FAIL: demo_sub/nested/demo output should contain 'Hamid'. Got: $out"
  exit 1
fi
if ! echo "$out" | grep -q "Ilias"; then
  echo "FAIL: demo_sub/nested/demo output should contain 'Ilias'. Got: $out"
  exit 1
fi
echo "PASS: demo_sub/nested/demo (George, Hamid, Ilias)"

echo "All nested package tests passed."
