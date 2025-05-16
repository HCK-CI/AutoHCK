#!/bin/bash

set -ex

test_name="$(basename "${0}" '.sh')"

cd "${WORKSPACE}"

bin/auto_hck --verbose test \
    --platform Win2022x64 \
    --drivers igb \
    --select-test-names "${WORKSPACE}/jenkins/sanity_tests" \
    --gthb_context_prefix "${test_name}: " \
    --commit "${GITHUB_COMMIT}"

mkdir -p "${test_name}"

unzip -o "${AUTO_HCK_WORKSPACE_PATH}/latest/*hlkx" -d "${test_name}"

cat "${test_name}/hck/data/PackageInfo.xml"
# Check that HLK package contains the expected test results
grep -e '<TestRollup Passed="1" Failed="0" NotRun="137" />' "${test_name}/hck/data/PackageInfo.xml"

# Check count of JSON results files
jsons=(${AUTO_HCK_WORKSPACE_PATH}/latest/Result_*.json)
if [ ${#jsons[@]} -ne 1 ]; then
    echo "Expected 1 json file, but found ${#jsons[@]}"
    exit 1
fi
