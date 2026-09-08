#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
TMP_DIR="$(cd "${TMP_DIR}" && pwd -P)"
ROOT_DIR="${TMP_DIR}/repo"
mkdir -p "${ROOT_DIR}/Scripts/lib"
cp "${SOURCE_ROOT}/Scripts/test-payments-device.sh" "${ROOT_DIR}/Scripts/"
cp "${SOURCE_ROOT}/Scripts/validate-release-artifact.py" "${ROOT_DIR}/Scripts/"
cp "${SOURCE_ROOT}/Scripts/lib/xcode-toolchain.sh" "${ROOT_DIR}/Scripts/lib/"
printf '#!/usr/bin/env bash\nexit 0\n' >"${ROOT_DIR}/Scripts/verify-device-identifiers.sh"

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
if [[ -e "${ROOT_DIR}/build" ]]; then
  echo "Validate-only mode must not create output directories." >&2
  exit 1
fi

assert_invalid_paths() {
  local label="$1"
  shift
  if env AIPEDOMETER_TEST_PAYMENTS_VALIDATE_PATHS_ONLY=1 \
    IPA_DIR=build/ipa ARCHIVE_PATH=build/ipa/AIPedometer.xcarchive \
    IPA_PATH=build/ipa/AIPedometer.ipa "$@" \
    bash "${ROOT_DIR}/Scripts/test-payments-device.sh" >"${TMP_DIR}/${label}.log" 2>&1; then
    echo "Expected ${label} output paths to fail." >&2
    exit 1
  fi
}

assert_invalid_paths parent-leaf IPA_DIR=build/ipa/..
assert_invalid_paths archive-root ARCHIVE_PATH=build/ipa
assert_invalid_paths archive-contains-output IPA_DIR=build/ipa/nested ARCHIVE_PATH=build/ipa/nested
assert_invalid_paths ipa-in-archive IPA_PATH=build/ipa/AIPedometer.xcarchive/output.ipa
assert_invalid_paths ipa-in-export IPA_PATH=build/ipa/export/AIPedometer.ipa

mkdir -p "${ROOT_DIR}/build/ipa" "${TMP_DIR}/outside"
printf 'keep\n' >"${TMP_DIR}/outside/sentinel"
ln -s "${TMP_DIR}/outside" "${ROOT_DIR}/build/ipa/escape"
assert_invalid_paths symlink-leaf IPA_DIR=build/ipa/escape
assert_invalid_paths archive-symlink-leaf ARCHIVE_PATH=build/ipa/escape
assert_invalid_paths ipa-symlink-leaf IPA_PATH=build/ipa/escape
assert_invalid_paths symlink-parent ARCHIVE_PATH=build/ipa/escape/created/archive.xcarchive
if [[ -e "${TMP_DIR}/outside/created" ]]; then
  echo "Path validation created a directory outside build/ipa." >&2
  exit 1
fi
assert_invalid_paths rejected-path-side-effect ARCHIVE_PATH=build/ipa/../created/archive.xcarchive
if [[ -e "${ROOT_DIR}/build/created" ]]; then
  echo "Rejected traversal created a directory before validation." >&2
  exit 1
fi
if [[ "$(<"${TMP_DIR}/outside/sentinel")" != keep ]]; then
  echo "Path validation changed an outside sentinel." >&2
  exit 1
fi
ln -s "${TMP_DIR}/outside/sentinel" "${ROOT_DIR}/build/ipa/xcodebuild-archive.log"
assert_invalid_paths artifact-symlink
rm "${ROOT_DIR}/build/ipa/xcodebuild-archive.log"

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
  "auth status --output table")
    if [[ "${MOCK_ASC_NO_CREDENTIALS:-0}" == "1" ]]; then
      printf 'No credentials stored\n'
    fi
    ;;
  "auth status")
    printf '{"credentials":[],"environmentCredentialsProvided":false,"environmentCredentialsComplete":false}\n'
    ;;
  "apps list"*)
    printf '{"data":[{"type":"apps","id":"%s","attributes":{"bundleId":"%s"}}]}\n' \
      "${TEST_SECRET_APP_ID}" "${APP_BUNDLE_ID}"
    ;;
  "sandbox list"*)
    printf '[{"id":"%s","email":"%s"}]\n' "${TEST_SECRET_SANDBOX_ID}" "${SANDBOX_TESTER_EMAIL}"
    ;;
  "testflight groups list"*)
    if [[ "$*" != *--paginate* ]]; then exit 65; fi
    if [[ "${MOCK_EXISTING_GROUP:-0}" == 1 ]]; then
      printf '{"data":[{"type":"betaGroups","id":"%s","attributes":{"name":"%s"}}]}\n' \
        "${TEST_SECRET_GROUP_ID}" "${TESTFLIGHT_GROUP_NAME}"
    else
      printf '{"data":[]}\n'
    fi
    ;;
  "testflight groups create"*)
    if [[ "${MOCK_EXISTING_GROUP:-0}" == 1 ]]; then exit 66; fi
    printf '{"data":{"type":"betaGroups","id":"%s","attributes":{"name":"%s"}}}\n' \
      "${TEST_SECRET_GROUP_ID}" "${TESTFLIGHT_GROUP_NAME}"
    ;;
  "testflight testers add"*|"testflight testers invite"*)
    printf '{"email":"%s"}\n' "${TESTFLIGHT_TESTER_EMAILS}"
    ;;
  "publish testflight"*)
    printf 'publish-control %s %s\n' "${ASC_KEY_ID}" "${ASC_ISSUER_ID}" >&2
    printf '{"app":"%s","group":"%s","testers":"%s"}\n' \
      "${TEST_SECRET_APP_ID}" \
      "${TEST_SECRET_GROUP_ID}" \
      "${TESTFLIGHT_TESTER_EMAILS}"
    if [[ "${MOCK_PAYMENT_FAILURE:-}" == publish ]]; then exit 33; fi
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
archive_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -exportPath) export_path="$2"; shift 2 ;;
    -archivePath) archive_path="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -n "${export_path}" ]]; then
  printf 'export-control %s %s\n' "${ASC_PRIVATE_KEY_PATH}" "${TESTFLIGHT_TESTER_EMAILS}"
  if [[ "${MOCK_PAYMENT_FAILURE:-}" == export ]]; then exit 32; fi
  mkdir -p "${export_path}"
  if [[ "${MOCK_PAYMENT_FAILURE:-}" == empty-ipa ]]; then
    : >"${export_path}/AIPedometer.ipa"
  else
    python3 - "${archive_path}" "${export_path}/AIPedometer.ipa" <<'PY'
import os
from pathlib import Path
import plistlib
import sys
import zipfile

applications = Path(sys.argv[1]) / "Products" / "Applications"
kind = os.environ.get("MOCK_IPA_CONFIGURATION", "valid")
with zipfile.ZipFile(sys.argv[2], "w") as ipa:
    for source in applications.rglob("*"):
        if not source.is_file():
            continue
        relative = source.relative_to(applications)
        if kind == "missing-widget" and "PlugIns" in relative.parts:
            continue
        data = source.read_bytes()
        if kind == "empty-executable" and relative.as_posix() == "MockRelease.app/MockRelease":
            data = b""
        if source.name == "Info.plist":
            info = plistlib.loads(data)
            if kind == "metadata-mismatch":
                info["CFBundleVersion"] = "8"
            if kind == "key-mismatch" and len(relative.parts) == 2:
                info["RevenueCatAPIKey"] = "appl_SYNTHETIC_DIFFERENT_KEY"
            data = plistlib.dumps(info)
        ipa.writestr("Payload/" + relative.as_posix(), data)
    if kind == "second-primary":
        ipa.writestr("Payload/Unexpected.app/", b"")
PY
  fi
else
  printf 'archive-control %s %s\n' "${ASC_KEY_ID}" "${ASC_ISSUER_ID}"
  if [[ "${MOCK_PAYMENT_FAILURE:-}" == archive ]]; then exit 31; fi
  python3 - "${archive_path}" <<'PY'
import os
from pathlib import Path
import plistlib
import sys

archive = Path(sys.argv[1])
application_path = "Applications/MockRelease.app"
app = archive / "Products" / application_path
app.mkdir(parents=True)
with (archive / "Info.plist").open("wb") as handle:
    plistlib.dump({"ApplicationProperties": {"ApplicationPath": application_path}}, handle)
info = {
    "CFBundleIdentifier": os.environ["APP_BUNDLE_ID"],
    "CFBundleShortVersionString": "1.2.3",
    "CFBundleVersion": "7",
    "CFBundleExecutable": "MockRelease",
    "RevenueCatAPIKey": "appl_SYNTHETIC_RELEASE_KEY",
}
kind = os.environ.get("MOCK_ARCHIVE_CONFIGURATION", "valid")
if kind == "test-key":
    info["RevenueCatAPIKey"] = "test_SYNTHETIC_DEVELOPMENT_KEY"
elif kind == "missing-key":
    del info["RevenueCatAPIKey"]
elif kind == "unresolved-key":
    info["RevenueCatAPIKey"] = "$(REVENUECAT_API_KEY)"
elif kind == "wrong-bundle":
    info["CFBundleIdentifier"] = "com.example.unexpected"
elif kind == "unresolved-version":
    info["CFBundleVersion"] = "$(CURRENT_PROJECT_VERSION)"
with (app / "Info.plist").open("wb") as handle:
    plistlib.dump(info, handle)
(app / "MockRelease").write_bytes(b"synthetic executable")
for role, relative, suffix, executable in (
    ("watch", "Watch/MockWatch.app", ".watch", "MockWatch"),
    ("widget", "PlugIns/MockWidget.appex", ".widgets", "MockWidget"),
):
    if kind == "missing-" + role:
        continue
    product = app / relative
    product.mkdir(parents=True)
    child = {
        "CFBundleIdentifier": os.environ["APP_BUNDLE_ID"] + suffix,
        "CFBundleShortVersionString": "1.2.3",
        "CFBundleVersion": "7",
        "CFBundleExecutable": executable,
    }
    if role == "watch":
        child["WKCompanionAppBundleIdentifier"] = os.environ["APP_BUNDLE_ID"]
    else:
        child["NSExtension"] = {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}
    if kind == role + "-version":
        child["CFBundleShortVersionString"] = "9.9"
    if kind == role + "-build":
        child["CFBundleVersion"] = "99"
    with (product / "Info.plist").open("wb") as handle:
        plistlib.dump(child, handle)
    (product / executable).write_bytes(b"" if kind == "empty-" + role + "-executable" else b"synthetic executable")
if kind == "second-primary":
    (archive / "Products/Applications/Unexpected.app").mkdir()
elif kind == "empty-app-executable":
    (app / "MockRelease").write_bytes(b"")
PY
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

run_mock_payment() {
env PATH="${MOCK_BIN}:${PATH}" \
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
  "$@" bash "${ROOT_DIR}/Scripts/test-payments-device.sh"
}

if ! run_mock_payment >"${TMP_DIR}/redaction.log" 2>&1; then
  echo "Expected ASC 5 JSON envelopes and command names to complete the mocked workflow." >&2
  exit 1
fi
run_mock_payment MOCK_EXISTING_GROUP=1 IPA_DIR="${TEST_OUTPUT_DIR}/existing-group" \
  >"${TMP_DIR}/existing-group.log" 2>&1
if ! grep -F 'Archive configuration validated.' "${TMP_DIR}/redaction.log" >/dev/null; then
  echo "Expected resolved archive configuration validation before export." >&2
  exit 1
fi
if ! grep -F 'IPA metadata matches validated archive.' "${TMP_DIR}/redaction.log" >/dev/null; then
  echo "Expected exported IPA validation before publishing." >&2
  exit 1
fi

python3 "${ROOT_DIR}/Scripts/validate-release-artifact.py" \
  --archive "${ROOT_DIR}/${TEST_OUTPUT_DIR}/AIPedometer.xcarchive" \
  --ipa "${ROOT_DIR}/${TEST_OUTPUT_DIR}/AIPedometer.ipa" \
  --bundle-id "${TEST_SECRET_BUNDLE_ID}" --version 1.2.3 --build 7 >"${TMP_DIR}/expected-version.log"
if python3 "${ROOT_DIR}/Scripts/validate-release-artifact.py" \
  --archive "${ROOT_DIR}/${TEST_OUTPUT_DIR}/AIPedometer.xcarchive" \
  --bundle-id "${TEST_SECRET_BUNDLE_ID}" --version 1.2.3 --build 8 >"${TMP_DIR}/wrong-expected-build.log" 2>&1; then
  echo "Expected independently specified build mismatch to fail." >&2
  exit 1
fi

for phase in archive export publish; do
  case "${phase}" in
    archive|export) artifact="xcodebuild-${phase}.log" ;;
    publish) artifact="asc-publish-testflight.json" ;;
  esac
  if ! grep -F "${phase}-control" "${ROOT_DIR}/${TEST_OUTPUT_DIR}/${artifact}" >/dev/null \
    || ! grep -F '[REDACTED]' "${ROOT_DIR}/${TEST_OUTPUT_DIR}/${artifact}" >/dev/null; then
    echo "Missing positive control or redaction in ${phase} log." >&2
    exit 1
  fi
done

for phase in archive export publish empty-ipa; do
  case "${phase}" in
    archive) expected_exit=31; forbidden_marker=export-control ;;
    export) expected_exit=32; forbidden_marker=publish-control ;;
    publish) expected_exit=33; forbidden_marker='^OK$' ;;
    empty-ipa) expected_exit=4; forbidden_marker=publish-control ;;
  esac
  payment_exit=0
  run_mock_payment MOCK_PAYMENT_FAILURE="${phase}" \
    IPA_DIR="${TEST_OUTPUT_DIR}/${phase}-failure" \
    >"${TMP_DIR}/${phase}-failure.log" 2>&1 || payment_exit=$?
  if [[ "${payment_exit}" -ne "${expected_exit}" ]]; then
    echo "Expected ${phase} failure exit ${expected_exit}; got ${payment_exit}." >&2
    exit 1
  fi
  if grep -E "${forbidden_marker}" "${TMP_DIR}/${phase}-failure.log" >/dev/null; then
    echo "Payment workflow continued after ${phase} failure." >&2
    exit 1
  fi
done

for configuration in test-key missing-key unresolved-key wrong-bundle unresolved-version; do
  payment_exit=0
  run_mock_payment MOCK_ARCHIVE_CONFIGURATION="${configuration}" \
    IPA_DIR="${TEST_OUTPUT_DIR}/${configuration}" \
    >"${TMP_DIR}/${configuration}.log" 2>&1 || payment_exit=$?
  if [[ "${payment_exit}" -ne 6 ]]; then
    echo "Expected archived ${configuration} to fail before export with exit 6; got ${payment_exit}." >&2
    exit 1
  fi
  if grep -E 'export-control|publish-control|SYNTHETIC_.*KEY' "${TMP_DIR}/${configuration}.log" >/dev/null; then
    echo "Invalid archive configuration proceeded or exposed its key." >&2
    exit 1
  fi
done

artifact_failures=0
for configuration in second-primary missing-watch missing-widget watch-version widget-build empty-app-executable empty-watch-executable empty-widget-executable; do
  payment_exit=0
  run_mock_payment MOCK_ARCHIVE_CONFIGURATION="${configuration}" \
    IPA_DIR="${TEST_OUTPUT_DIR}/archive-${configuration}" \
    >"${TMP_DIR}/archive-${configuration}.log" 2>&1 || payment_exit=$?
  if [[ "${payment_exit}" -ne 6 ]] \
    || grep -E 'export-control|publish-control' "${TMP_DIR}/archive-${configuration}.log" >/dev/null; then
    echo "Expected archive ${configuration} to fail before export with exit 6; got ${payment_exit}." >&2
    artifact_failures=$((artifact_failures + 1))
  fi
done
for configuration in second-primary missing-widget empty-executable metadata-mismatch key-mismatch; do
  payment_exit=0
  run_mock_payment MOCK_IPA_CONFIGURATION="${configuration}" \
    IPA_DIR="${TEST_OUTPUT_DIR}/ipa-${configuration}" \
    >"${TMP_DIR}/ipa-${configuration}.log" 2>&1 || payment_exit=$?
  if [[ "${payment_exit}" -ne 6 ]] \
    || grep -F publish-control "${TMP_DIR}/ipa-${configuration}.log" >/dev/null; then
    echo "Expected IPA ${configuration} to fail before publishing with exit 6; got ${payment_exit}." >&2
    artifact_failures=$((artifact_failures + 1))
  fi
done
if [[ "${artifact_failures}" -ne 0 ]]; then exit 1; fi

sensitive_outputs=(
  "${TMP_DIR}/redaction.log"
  "${ROOT_DIR}/${TEST_OUTPUT_DIR}/xcodebuild-archive.log"
  "${ROOT_DIR}/${TEST_OUTPUT_DIR}/xcodebuild-export.log"
  "${ROOT_DIR}/${TEST_OUTPUT_DIR}/asc-publish-testflight.json"
  "${TMP_DIR}/archive-failure.log"
  "${TMP_DIR}/export-failure.log"
  "${TMP_DIR}/publish-failure.log"
  "${TMP_DIR}/empty-ipa-failure.log"
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
