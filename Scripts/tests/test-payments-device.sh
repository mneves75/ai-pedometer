#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

if ! AIPEDOMETER_TEST_PAYMENTS_VALIDATE_PATHS_ONLY=1 \
  IPA_DIR="build/ipa" \
  ARCHIVE_PATH="build/ipa/AIPedometer.xcarchive" \
  IPA_PATH="build/ipa/AIPedometer.ipa" \
  bash "${ROOT_DIR}/Scripts/test-payments-device.sh" >"${TMP_DIR}/valid.log"; then
  echo "Expected default TestFlight output paths to validate." >&2
  exit 1
fi

if ! rg -n "Path validation OK" "${TMP_DIR}/valid.log" >/dev/null; then
  echo "Expected path validation success marker." >&2
  exit 1
fi

if AIPEDOMETER_TEST_PAYMENTS_VALIDATE_PATHS_ONLY=1 \
  IPA_DIR="${TMP_DIR}/outside" \
  bash "${ROOT_DIR}/Scripts/test-payments-device.sh" >"${TMP_DIR}/outside.log" 2>&1; then
  echo "Expected absolute output path outside build/ipa to fail." >&2
  exit 1
fi

if AIPEDOMETER_TEST_PAYMENTS_VALIDATE_PATHS_ONLY=1 \
  IPA_DIR="build/ipa" \
  ARCHIVE_PATH="build/ipa/../AIPedometer.xcarchive" \
  bash "${ROOT_DIR}/Scripts/test-payments-device.sh" >"${TMP_DIR}/traversal.log" 2>&1; then
  echo "Expected traversal output path outside build/ipa to fail." >&2
  exit 1
fi

MOCK_BIN="${TMP_DIR}/bin"
mkdir -p "${MOCK_BIN}"

cat >"${MOCK_BIN}/asc" <<'MOCK_ASC'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  "auth status")
    if [[ "${MOCK_ASC_NO_CREDENTIALS:-0}" == "1" ]]; then
      printf 'No credentials stored\n'
    fi
    ;;
  "apps list"*)
    printf '[{"id":"%s"}]\n' "${TEST_SECRET_APP_ID}"
    ;;
  "sandbox list"*)
    printf '[{"id":"%s","email":"%s"}]\n' "${TEST_SECRET_SANDBOX_ID}" "${SANDBOX_TESTER_EMAIL}"
    ;;
  "testflight beta-groups list"*)
    printf '[]\n'
    ;;
  "testflight beta-groups create"*)
    printf '{"id":"%s","name":"%s"}\n' "${TEST_SECRET_GROUP_ID}" "${TESTFLIGHT_GROUP_NAME}"
    ;;
  "testflight beta-testers add"*|"testflight beta-testers invite"*)
    printf '{"email":"%s"}\n' "${TESTFLIGHT_TESTER_EMAILS}"
    ;;
  "publish testflight"*)
    printf '{"app":"%s","group":"%s","testers":"%s"}\n' \
      "${TEST_SECRET_APP_ID}" \
      "${TEST_SECRET_GROUP_ID}" \
      "${TESTFLIGHT_TESTER_EMAILS}"
    ;;
  *)
    echo "Unexpected asc arguments: $*" >&2
    exit 64
    ;;
esac
MOCK_ASC
chmod +x "${MOCK_BIN}/asc"

cat >"${MOCK_BIN}/xcodebuild" <<'MOCK_XCODEBUILD'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "-version" ]]; then
  printf 'Xcode 26.6\nBuild version TEST\n'
  exit 0
fi

export_path=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-exportPath" ]]; then
    export_path="$2"
    break
  fi
  shift
done

if [[ -n "${export_path}" ]]; then
  mkdir -p "${export_path}"
  : >"${export_path}/AIPedometer.ipa"
fi
MOCK_XCODEBUILD
chmod +x "${MOCK_BIN}/xcodebuild"

TEST_OUTPUT_DIR="build/ipa/redaction-test-${$}"
TEST_SECRET_KEY_ID="TEST_KEY_ID_SHOULD_NOT_APPEAR"
TEST_SECRET_ISSUER_ID="TEST_ISSUER_ID_SHOULD_NOT_APPEAR"
TEST_SECRET_KEY_PATH="/tmp/TEST_KEY_PATH_SHOULD_NOT_APPEAR.p8"
TEST_SECRET_APP_ID="TEST_APP_ID_SHOULD_NOT_APPEAR"
TEST_SECRET_SANDBOX_ID="TEST_SANDBOX_ID_SHOULD_NOT_APPEAR"
TEST_SECRET_GROUP_ID="TEST_GROUP_ID_SHOULD_NOT_APPEAR"
TEST_SECRET_BUNDLE_ID="com.example.TEST_BUNDLE_SHOULD_NOT_APPEAR"
TEST_SECRET_GROUP_NAME="TEST_GROUP_NAME_SHOULD_NOT_APPEAR"
TEST_SECRET_SANDBOX_EMAIL="sandbox-secret@example.invalid"
TEST_SECRET_TESTER_EMAILS="tester-one@example.invalid,tester-two@example.invalid"

cleanup_redaction_output() {
  rm -rf -- "${ROOT_DIR:?}/${TEST_OUTPUT_DIR:?}"
}
trap 'cleanup_redaction_output; cleanup' EXIT

PATH="${MOCK_BIN}:${PATH}" \
  DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
  ASC_KEY_ID="${TEST_SECRET_KEY_ID}" \
  ASC_ISSUER_ID="${TEST_SECRET_ISSUER_ID}" \
  ASC_PRIVATE_KEY_PATH="${TEST_SECRET_KEY_PATH}" \
  APP_BUNDLE_ID="${TEST_SECRET_BUNDLE_ID}" \
  TESTFLIGHT_GROUP_NAME="${TEST_SECRET_GROUP_NAME}" \
  SANDBOX_TESTER_EMAIL="${TEST_SECRET_SANDBOX_EMAIL}" \
  TESTFLIGHT_TESTER_EMAILS="${TEST_SECRET_TESTER_EMAILS}" \
  TEST_SECRET_APP_ID="${TEST_SECRET_APP_ID}" \
  TEST_SECRET_SANDBOX_ID="${TEST_SECRET_SANDBOX_ID}" \
  TEST_SECRET_GROUP_ID="${TEST_SECRET_GROUP_ID}" \
  IPA_DIR="${TEST_OUTPUT_DIR}" \
  bash "${ROOT_DIR}/Scripts/test-payments-device.sh" >"${TMP_DIR}/redaction.log" 2>&1

sensitive_outputs=(
  "${TMP_DIR}/redaction.log"
  "${ROOT_DIR}/${TEST_OUTPUT_DIR}/xcodebuild-archive.log"
  "${ROOT_DIR}/${TEST_OUTPUT_DIR}/xcodebuild-export.log"
  "${ROOT_DIR}/${TEST_OUTPUT_DIR}/asc-publish-testflight.json"
)
for sensitive_output in "${sensitive_outputs[@]}"; do
  sensitive_index=0
  for sensitive_value in \
    "${TEST_SECRET_KEY_ID}" \
    "${TEST_SECRET_ISSUER_ID}" \
    "${TEST_SECRET_KEY_PATH}" \
    "${TEST_SECRET_APP_ID}" \
    "${TEST_SECRET_SANDBOX_ID}" \
    "${TEST_SECRET_GROUP_ID}" \
    "${TEST_SECRET_BUNDLE_ID}" \
    "${TEST_SECRET_GROUP_NAME}" \
    "${TEST_SECRET_SANDBOX_EMAIL}" \
    "tester-one@example.invalid" \
    "tester-two@example.invalid"; do
    sensitive_index=$((sensitive_index + 1))
    if grep -F -- "${sensitive_value}" "${sensitive_output}" >/dev/null; then
      echo "Sensitive payment metadata item ${sensitive_index} leaked to output." >&2
      exit 1
    fi
  done
done

set +e
PATH="${MOCK_BIN}:${PATH}" \
  MOCK_ASC_NO_CREDENTIALS=1 \
  DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
  ASC_KEY_ID="${TEST_SECRET_KEY_ID}" \
  ASC_ISSUER_ID="${TEST_SECRET_ISSUER_ID}" \
  ASC_PRIVATE_KEY_PATH="${TEST_SECRET_KEY_PATH}" \
  bash "${ROOT_DIR}/Scripts/test-payments-device.sh" >"${TMP_DIR}/missing-credentials.log" 2>&1
missing_credentials_status=$?
set -e

if [[ ${missing_credentials_status} -ne 2 ]]; then
  echo "Expected missing credentials guidance to exit 2; got ${missing_credentials_status}." >&2
  exit 1
fi
for sensitive_value in \
  "${TEST_SECRET_KEY_ID}" \
  "${TEST_SECRET_ISSUER_ID}" \
  "${TEST_SECRET_KEY_PATH}"; do
  if grep -F -- "${sensitive_value}" "${TMP_DIR}/missing-credentials.log" >/dev/null; then
    echo "Credential metadata leaked to authentication guidance." >&2
    exit 1
  fi
done

echo "test-payments-device.sh path validation and redaction tests passed."
