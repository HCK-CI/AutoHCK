#!/bin/bash

set -ex

test_name="$(basename "${0}" '.sh')"

cd "${WORKSPACE}"

# Create a temporary directory with a known marker file to exercise --test-binaries-path
tmp_test_binaries="$(mktemp -d)"
echo "dummy_ci" > "${tmp_test_binaries}/dummy_ci_marker.txt"
trap 'rm -rf "$tmp_test_binaries"' EXIT

bin/auto_hck --verbose functest \
    --platform Win2025x64 \
    --test-binaries-path "${tmp_test_binaries}" \
    --category dummy \
    --gthb_context_prefix "${test_name}: " \
    --commit "${GITHUB_COMMIT}"

cat "${AUTO_HCK_WORKSPACE_PATH}/latest/functest_results.json"
# Check that all 6 test cases passed
grep -e '"passed": 6,' "${AUTO_HCK_WORKSPACE_PATH}/latest/functest_results.json"
