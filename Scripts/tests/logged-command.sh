#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

LOGGED_COMMAND_SCRIPT="${ROOT_DIR}/Scripts/lib/logged-command.sh"
if [[ ! -f "${LOGGED_COMMAND_SCRIPT}" ]]; then
  echo "Missing logged-command implementation: ${LOGGED_COMMAND_SCRIPT}" >&2
  exit 1
fi
# Resolved from the repository root above.
# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${LOGGED_COMMAND_SCRIPT}"

COMMAND_FIXTURE="${TMP_DIR}/command.sh"
cat >"${COMMAND_FIXTURE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "stdout marker"
echo "NSMachErrorDomain: server died" >&2
exit 42
EOF
chmod +x "${COMMAND_FIXTURE}"

COMMAND_LOG="${TMP_DIR}/command.log"
set +e
aipedometer_run_logged "${COMMAND_LOG}" "${COMMAND_FIXTURE}" >/dev/null
exit_code=$?
set -e

if [[ ${exit_code} -ne 42 ]]; then
  echo "Expected pipefail to preserve command exit 42; got ${exit_code}." >&2
  exit 1
fi
if ! grep -Fqx "stdout marker" "${COMMAND_LOG}"; then
  echo "Expected stdout in the tee log." >&2
  exit 1
fi
if ! grep -Fqx "NSMachErrorDomain: server died" "${COMMAND_LOG}"; then
  echo "Expected stderr in the tee log for retry classification." >&2
  exit 1
fi
if ! /bin/bash "${ROOT_DIR}/Scripts/simulator-retry-classifier.sh" "${COMMAND_LOG}"; then
  echo "Expected the stderr-only simulator failure to trigger retry classification." >&2
  exit 1
fi

NO_PIPEFAIL_LOG="${TMP_DIR}/no-pipefail.log"
set +e
/bin/zsh -c 'source "$1"; aipedometer_run_logged "$2" "$3" >/dev/null' \
  zsh "${LOGGED_COMMAND_SCRIPT}" "${NO_PIPEFAIL_LOG}" "${COMMAND_FIXTURE}"
no_pipefail_exit_code=$?
set -e

if [[ ${no_pipefail_exit_code} -ne 42 ]]; then
  echo "Expected the helper to preserve exit 42 without caller pipefail; got ${no_pipefail_exit_code}." >&2
  exit 1
fi
if ! grep -Fqx "NSMachErrorDomain: server died" "${NO_PIPEFAIL_LOG}"; then
  echo "Expected stderr in the no-pipefail caller log." >&2
  exit 1
fi

echo "logged-command.sh tests passed."
