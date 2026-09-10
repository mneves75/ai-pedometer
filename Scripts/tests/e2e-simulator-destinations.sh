#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

MOCK_BIN="${TMP_DIR}/bin"
XCRUN_LOG="${TMP_DIR}/xcrun.log"
XCODEBUILD_LOG="${TMP_DIR}/xcodebuild.log"
DEVICE_JSON="${TMP_DIR}/devices.json"
mkdir -p "${MOCK_BIN}"

ios_a=11111111
ios_b=2222
ios_c=3333
ios_d=4444
ios_e=555555555555
IOS_ID="${ios_a}-${ios_b}-${ios_c}-${ios_d}-${ios_e}"
watch_a=AAAAAAAA
watch_b=BBBB
watch_c=CCCC
watch_d=DDDD
watch_e=EEEEEEEEEEEE
WATCH_ID="${watch_a}-${watch_b}-${watch_c}-${watch_d}-${watch_e}"
unavailable_a=99999999
UNAVAILABLE_ID="${unavailable_a}-${ios_b}-${ios_c}-${ios_d}-${ios_e}"
unknown_a=77777777
UNKNOWN_ID="${unknown_a}-${ios_b}-${ios_c}-${ios_d}-${ios_e}"

cat > "${DEVICE_JSON}" <<EOF
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
      {"name":"iPhone Test","udid":"${IOS_ID}","state":"Booted","isAvailable":true},
      {"name":"iPhone Unavailable","udid":"${UNAVAILABLE_ID}","state":"Shutdown","isAvailable":false}
    ],
    "com.apple.CoreSimulator.SimRuntime.watchOS-26-2": [
      {"name":"Apple Watch Test","udid":"${WATCH_ID}","state":"Shutdown","isAvailable":true}
    ]
  }
}
EOF

cat > "${MOCK_BIN}/xcodebuild" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${XCODEBUILD_LOG}"
if [[ "${1:-}" == "-version" ]]; then
  printf 'Xcode 26.6\nBuild version TEST\n'
  exit 0
fi
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-resultBundlePath" ]]; then
    mkdir -p "$2"
    break
  fi
  shift
done
EOF

cat > "${MOCK_BIN}/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${XCRUN_LOG}"
case "$*" in
  'simctl list devices --json')
    /bin/cat "${DEVICE_JSON}"
    ;;
  'xcresulttool get test-results summary '*)
    printf '%s\n' '{"result":"Passed","totalTestCount":1,"passedTests":1,"failedTests":0,"skippedTests":0}'
    ;;
esac
EOF

cat > "${MOCK_BIN}/open" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "${MOCK_BIN}/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "${MOCK_BIN}/xcodebuild" "${MOCK_BIN}/xcrun" "${MOCK_BIN}/open" "${MOCK_BIN}/sleep"

run_e2e() {
  local label="$1"
  shift
  env -u GITHUB_ACTIONS -u RUNNER_ENVIRONMENT \
    PATH="${MOCK_BIN}:${PATH}" \
    AIPEDOMETER_XCODE_FALLBACK="${TMP_DIR}" \
    XCRUN_LOG="${XCRUN_LOG}" \
    XCODEBUILD_LOG="${XCODEBUILD_LOG}" \
    DEVICE_JSON="${DEVICE_JSON}" \
    E2E_OUT_DIR="${TMP_DIR}/output-${label}" \
    E2E_DERIVED_DATA_ROOT="${TMP_DIR}/derived-${label}" \
    E2E_ENABLE_WIDGETS=0 \
    E2E_ENABLE_SCREENSHOTS=0 \
    E2E_UNIT_RESTART_MAX=1 \
    E2E_UI_RESTART_MAX=1 \
    "$@" bash "${ROOT_DIR}/Scripts/e2e-simulator.sh"
}

assert_preflight_failure() {
  local label="$1"
  local message="$2"
  shift 2
  : > "${XCRUN_LOG}"
  : > "${XCODEBUILD_LOG}"

  if run_e2e "${label}" "$@" > "${TMP_DIR}/${label}.log" 2>&1; then
    echo "Expected ${label} destination preflight to fail." >&2
    exit 1
  fi
  if ! grep -Fq "${message}" "${TMP_DIR}/${label}.log"; then
    echo "Missing ${label} destination error: ${message}" >&2
    exit 1
  fi
  if [[ -e "${TMP_DIR}/output-${label}" || -e "${TMP_DIR}/derived-${label}" ]]; then
    echo "Destination preflight created output for ${label}." >&2
    exit 1
  fi
  if grep -Eq '^simctl (boot|bootstatus|erase|shutdown) ' "${XCRUN_LOG}"; then
    echo "Destination preflight mutated a simulator for ${label}." >&2
    exit 1
  fi
}

assert_success() {
  local label="$1"
  shift
  : > "${XCRUN_LOG}"
  : > "${XCODEBUILD_LOG}"
  run_e2e "${label}" "$@" > "${TMP_DIR}/${label}.log" 2>&1
  grep -Fqx 'OK' "${TMP_DIR}/${label}.log"
}

assert_preflight_failure local-missing E2E_IOS_UDID E2E_ENABLE_WATCH=0
assert_preflight_failure generic-ci E2E_IOS_UDID CI=true E2E_ENABLE_WATCH=0
assert_preflight_failure booted-string 'simulador iOS desconhecido' E2E_IOS_UDID=booted E2E_ENABLE_WATCH=0
assert_preflight_failure unknown 'simulador iOS desconhecido' E2E_IOS_UDID="${UNKNOWN_ID}" E2E_ENABLE_WATCH=0
assert_preflight_failure unavailable 'simulador iOS indisponivel' E2E_IOS_UDID="${UNAVAILABLE_ID}" E2E_ENABLE_WATCH=0
assert_preflight_failure wrong-family 'nao pertence a familia iOS' E2E_IOS_UDID="${WATCH_ID}" E2E_ENABLE_WATCH=0
assert_preflight_failure watch-missing E2E_WATCH_UDID E2E_IOS_UDID="${IOS_ID}" E2E_ENABLE_WATCH=1
assert_preflight_failure legacy-ios E2E_IOS_DEST E2E_IOS_DEST=legacy E2E_ENABLE_WATCH=0
assert_preflight_failure legacy-watch E2E_WATCH_DEST E2E_WATCH_DEST=legacy E2E_ENABLE_WATCH=0

assert_success explicit-ios E2E_IOS_UDID="${IOS_ID}" E2E_ENABLE_WATCH=0
grep -F -- "-destination platform=iOS Simulator,id=${IOS_ID}" "${XCODEBUILD_LOG}" >/dev/null

assert_success explicit-watch E2E_IOS_UDID="${IOS_ID}" E2E_WATCH_UDID="${WATCH_ID}" E2E_ENABLE_WATCH=1
grep -F -- "-destination platform=iOS Simulator,id=${IOS_ID}" "${XCODEBUILD_LOG}" >/dev/null
grep -F -- "-destination platform=watchOS Simulator,id=${WATCH_ID}" "${XCODEBUILD_LOG}" >/dev/null

assert_success hosted-auto GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=github-hosted E2E_ENABLE_WATCH=0
grep -F -- "-destination platform=iOS Simulator,id=${IOS_ID}" "${XCODEBUILD_LOG}" >/dev/null

assert_success erase-selected E2E_IOS_UDID="${IOS_ID}" E2E_ENABLE_WATCH=0 E2E_ERASE_IOS_SIM=1
grep -Fqx "simctl erase ${IOS_ID}" "${XCRUN_LOG}"
if grep -F "simctl erase " "${XCRUN_LOG}" | grep -Fv "${IOS_ID}" >/dev/null; then
  echo "Erase touched a simulator other than the selected iOS ID." >&2
  exit 1
fi

echo "e2e-simulator.sh destination tests passed."
