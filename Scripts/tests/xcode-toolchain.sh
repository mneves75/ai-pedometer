#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
EXTERNAL_26="${TMP_DIR}/Xcode-26.app/Contents/Developer"
EXTERNAL_27="${TMP_DIR}/Xcode-27.app/Contents/Developer"
FALLBACK_26="${TMP_DIR}/Xcode-stable.app/Contents/Developer"
INVALID_FALLBACK="${TMP_DIR}/Xcode-invalid.app/Contents/Developer"
mkdir -p "${FAKE_BIN}" "${EXTERNAL_26}" "${EXTERNAL_27}" "${FALLBACK_26}" "${INVALID_FALLBACK}"

printf '%s\n' '26.6' >"${EXTERNAL_26}/version"
printf '%s\n' '27.0' >"${EXTERNAL_27}/version"
printf '%s\n' '26.5' >"${FALLBACK_26}/version"
printf '%s\n' '25.4' >"${INVALID_FALLBACK}/version"

cat >"${FAKE_BIN}/xcodebuild" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == "-version" ]]
[[ -f "${DEVELOPER_DIR}/version" ]]
version="$(<"${DEVELOPER_DIR}/version")"
printf 'Xcode %s\nBuild version TEST\n' "${version}"
EOF
chmod +x "${FAKE_BIN}/xcodebuild"

cat >"${FAKE_BIN}/xcode-select" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == "-p" ]]
printf '%s\n' "${FAKE_XCODE_SELECT_PATH}"
EOF
chmod +x "${FAKE_BIN}/xcode-select"

run_selector() {
  local developer_dir="$1"
  local fallback_dir="$2"
  local selected_dir="${3:-${INVALID_FALLBACK}}"
  PATH="${FAKE_BIN}:${PATH}" \
    DEVELOPER_DIR="${developer_dir}" \
    FAKE_XCODE_SELECT_PATH="${selected_dir}" \
    AIPEDOMETER_XCODE_26_FALLBACK="${fallback_dir}" \
    /bin/bash -c '
      set -euo pipefail
      source "$1"
      aipedometer_select_xcode_26
      printf "SELECTED=%s\n" "${DEVELOPER_DIR}"
    ' _ "${ROOT_DIR}/Scripts/lib/xcode-toolchain.sh"
}

selected_output="$(run_selector "" "${INVALID_FALLBACK}" "${EXTERNAL_26}")"
if [[ "${selected_output}" != *"SELECTED=${EXTERNAL_26}"* ]]; then
  echo "Expected the Xcode selected by xcode-select to be used when DEVELOPER_DIR is unset." >&2
  exit 1
fi

external_output="$(run_selector "${EXTERNAL_26}" "${FALLBACK_26}")"
if [[ "${external_output}" != *"SELECTED=${EXTERNAL_26}"* ]]; then
  echo "Expected a valid external Xcode 26 to be preserved." >&2
  exit 1
fi

fallback_output="$(run_selector "${EXTERNAL_27}" "${FALLBACK_26}")"
if [[ "${fallback_output}" != *"SELECTED=${FALLBACK_26}"* ]]; then
  echo "Expected an external non-26 Xcode to fall back to stable Xcode 26." >&2
  exit 1
fi

FAILURE_LOG="${TMP_DIR}/failure.log"
if run_selector "${EXTERNAL_27}" "${INVALID_FALLBACK}" >"${FAILURE_LOG}" 2>&1; then
  echo "Expected selection to fail when no Xcode 26 is available." >&2
  exit 1
fi

EXPECTED_ERROR="ERRO: Xcode 26.x nao encontrado. Instale o Xcode 26 em /Applications/Xcode.app ou defina DEVELOPER_DIR para um Xcode 26.x valido."
if ! grep -Fqx "${EXPECTED_ERROR}" "${FAILURE_LOG}"; then
  echo "Expected exact Xcode 26 remediation." >&2
  cat "${FAILURE_LOG}" >&2
  exit 1
fi

echo "xcode-toolchain.sh tests passed."
