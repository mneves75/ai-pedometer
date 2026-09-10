#!/usr/bin/env bash
set -euo pipefail

# Fixture-driven tests for the toolchain selector.
#
# These deliberately do NOT assert anything about the host's real Xcode — that is the job of
# Scripts/preflight.sh, which is what actually catches "the pinned toolchain is not installed".
# The prior version of this suite passed while the selector was dead on the host, so the two
# concerns are kept separate on purpose: this file pins selection LOGIC, preflight pins the HOST.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
XCODE_26="${TMP_DIR}/Xcode-26.app/Contents/Developer"
XCODE_27="${TMP_DIR}/Xcode-27.app/Contents/Developer"
XCODE_25="${TMP_DIR}/Xcode-25.app/Contents/Developer"
mkdir -p "${FAKE_BIN}" "${XCODE_26}" "${XCODE_27}" "${XCODE_25}"

printf '%s\n' '26.6' >"${XCODE_26}/version"
printf '%s\n' '27.0' >"${XCODE_27}/version"
printf '%s\n' '25.4' >"${XCODE_25}/version"

cat >"${FAKE_BIN}/xcodebuild" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == "-version" ]]
[[ -f "${DEVELOPER_DIR}/version" ]]
version="$(<"${DEVELOPER_DIR}/version")"
printf 'Xcode %s\nBuild version FAKE%s\n' "${version}" "${version//./}"
EOF
chmod +x "${FAKE_BIN}/xcodebuild"

cat >"${FAKE_BIN}/xcode-select" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == "-p" ]]
printf '%s\n' "${FAKE_XCODE_SELECT_PATH}"
EOF
chmod +x "${FAKE_BIN}/xcode-select"

# run_selector <developer_dir> <fallback_dir> <xcode-select path> [majors] [pinned dir]
run_selector() {
  PATH="${FAKE_BIN}:${PATH}" \
    DEVELOPER_DIR="$1" \
    AIPEDOMETER_XCODE_FALLBACK="$2" \
    FAKE_XCODE_SELECT_PATH="$3" \
    AIPEDOMETER_SUPPORTED_XCODE_MAJORS="${4:-26 27}" \
    AIPEDOMETER_XCODE_DEVELOPER_DIR="${5:-}" \
    /bin/bash -c '
      set -uo pipefail
      source "$1"
      aipedometer_select_xcode || exit 1
      printf "SELECTED=%s VERSION=%s BUILD=%s\n" \
        "${DEVELOPER_DIR}" "${AIPEDOMETER_RESOLVED_XCODE_VERSION}" "${AIPEDOMETER_RESOLVED_XCODE_BUILD}"
    ' _ "${ROOT_DIR}/Scripts/lib/xcode-toolchain.sh"
}

fail() { echo "$1" >&2; exit 1; }

# Both supported majors are accepted — this is the regression that a hard 26 pin caused.
out="$(run_selector "${XCODE_26}" "${XCODE_25}" "${XCODE_25}")"
[[ "${out}" == *"SELECTED=${XCODE_26}"* ]] || fail "Expected Xcode 26 from DEVELOPER_DIR to be accepted."

out="$(run_selector "${XCODE_27}" "${XCODE_25}" "${XCODE_25}")"
[[ "${out}" == *"SELECTED=${XCODE_27}"* ]] || fail "Expected Xcode 27 from DEVELOPER_DIR to be accepted."

# The resolved version AND build are exported, so release evidence is attributable.
[[ "${out}" == *"VERSION=27.0"* ]] || fail "Expected the resolved version to be exported."
[[ "${out}" == *"BUILD=FAKE270"* ]] || fail "Expected the resolved build to be exported."

# An unsupported DEVELOPER_DIR falls through to xcode-select, then to the fallback.
out="$(run_selector "${XCODE_25}" "${XCODE_25}" "${XCODE_27}")"
[[ "${out}" == *"SELECTED=${XCODE_27}"* ]] || fail "Expected fallthrough to the xcode-select toolchain."

out="$(run_selector "${XCODE_25}" "${XCODE_26}" "${XCODE_25}")"
[[ "${out}" == *"SELECTED=${XCODE_26}"* ]] || fail "Expected fallthrough to AIPEDOMETER_XCODE_FALLBACK."

# An explicit pin wins over every other candidate.
out="$(run_selector "${XCODE_27}" "${XCODE_27}" "${XCODE_27}" "26 27" "${XCODE_26}")"
[[ "${out}" == *"SELECTED=${XCODE_26}"* ]] || fail "Expected AIPEDOMETER_XCODE_DEVELOPER_DIR to win."

# NEGATIVE CONTROL 1: nothing supported anywhere must fail and name every rejected candidate.
LOG="${TMP_DIR}/no-supported.log"
if run_selector "${XCODE_25}" "${XCODE_25}" "${XCODE_25}" >"${LOG}" 2>&1; then
  fail "Expected selection to fail when no supported Xcode exists."
fi
grep -q "nenhum Xcode suportado encontrado" "${LOG}" || fail "Expected the no-toolchain error."
grep -q "rejeitado: DEVELOPER_DIR=${XCODE_25} (Xcode 25.4)" "${LOG}" \
  || { cat "${LOG}" >&2; fail "Expected the rejected candidate and the version actually seen."; }

# NEGATIVE CONTROL 2: an explicit pin that is unusable must fail rather than silently drift.
LOG="${TMP_DIR}/bad-pin.log"
if run_selector "${XCODE_26}" "${XCODE_26}" "${XCODE_26}" "26 27" "${XCODE_25}" >"${LOG}" 2>&1; then
  fail "Expected an unsupported explicit pin to fail instead of falling back."
fi
grep -q "AIPEDOMETER_XCODE_DEVELOPER_DIR=${XCODE_25}" "${LOG}" || fail "Expected the bad-pin error."

echo "xcode-toolchain.sh tests passed."
