#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
COMMAND_LOG="${TMP_DIR}/xcrun.log"
mkdir -p "${FAKE_BIN}"

cat >"${FAKE_BIN}/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${SIMULATOR_COMMAND_LOG}"
EOF
chmod +x "${FAKE_BIN}/xcrun"

PATH="${FAKE_BIN}:${PATH}"
SIMULATOR_COMMAND_LOG="${COMMAND_LOG}"
export PATH SIMULATOR_COMMAND_LOG

LIFECYCLE_SCRIPT="${ROOT_DIR}/Scripts/lib/simulator-lifecycle.sh"
if [[ ! -f "${LIFECYCLE_SCRIPT}" ]]; then
  echo "Missing simulator lifecycle implementation: ${LIFECYCLE_SCRIPT}" >&2
  exit 1
fi
# Resolved from the repository root above.
# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${LIFECYCLE_SCRIPT}"
aipedometer_prepare_simulator "IOS-TEST" 1
aipedometer_prepare_simulator "WATCH-TEST" 0

EXPECTED_LOG="${TMP_DIR}/expected.log"
cat >"${EXPECTED_LOG}" <<'EOF'
simctl shutdown IOS-TEST
simctl erase IOS-TEST
simctl boot IOS-TEST
simctl bootstatus IOS-TEST -b
simctl boot WATCH-TEST
simctl bootstatus WATCH-TEST -b
EOF

if ! cmp -s "${EXPECTED_LOG}" "${COMMAND_LOG}"; then
  echo "Expected each simulator to boot once and wait after its final boot." >&2
  diff -u "${EXPECTED_LOG}" "${COMMAND_LOG}" >&2 || true
  exit 1
fi

echo "simulator-lifecycle.sh tests passed."
