#!/bin/bash

set -ex

test_name="$(basename "${0}" '.sh')"

cd "${WORKSPACE}"

bin/auto_hck --verbose functest \
    --platform Win2025x64 \
    --drivers Balloon \
    --driver-path "${VIRTIO_WIN_PATH}/amd64/2k25/" \
    --category balloon_driver_tests \
    --gthb_context_prefix "${test_name}: " \
    --commit "${GITHUB_COMMIT}"

cat "${AUTO_HCK_WORKSPACE_PATH}/latest/functest_results.json"
# Check that HLK package contains the expected test results
grep -e '"passed": 3,' "${AUTO_HCK_WORKSPACE_PATH}/latest/functest_results.json"
