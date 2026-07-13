#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

set +e
HELP_OUTPUT="$(/bin/bash "${ROOT_DIR}/Scripts/install-on-device.sh" --help 2>&1)"
HELP_STATUS=$?
set -e

if [[ ${HELP_STATUS} -ne 0 ]]; then
  echo "Expected --help to exit successfully under the system Bash." >&2
  echo "${HELP_OUTPUT}" >&2
  exit 1
fi

if [[ "${HELP_OUTPUT}" == *"unbound variable"* ]]; then
  echo "Expected --help cleanup to avoid empty-array errors under Bash 3.2." >&2
  exit 1
fi

FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${FAKE_BIN}"

XCODEBUILD_LOG="${TMP_DIR}/xcodebuild.log"
XCRUN_LOG="${TMP_DIR}/xcrun.log"
APP_DIR="${TMP_DIR}/DerivedData/Build/Products/Debug-iphoneos/Fake.app"
WATCH_APP_DIR="${TMP_DIR}/DerivedData/Build/Products/Debug-watchos/FakeWatch.app"
mkdir -p "$(dirname "${APP_DIR}")"
mkdir -p "$(dirname "${WATCH_APP_DIR}")"

ln -s "${ROOT_DIR}/Scripts/tests/fixtures/mock-xcodebuild.sh" "${FAKE_BIN}/xcodebuild"
ln -s "${ROOT_DIR}/Scripts/tests/fixtures/mock-xcrun.sh" "${FAKE_BIN}/xcrun"

PATH="${FAKE_BIN}:${PATH}" \
XCODEBUILD_LOG="${XCODEBUILD_LOG}" \
XCRUN_LOG="${XCRUN_LOG}" \
APP_PRODUCTS_DIR="$(dirname "${APP_DIR}")" \
WATCH_PRODUCTS_DIR="$(dirname "${WATCH_APP_DIR}")" \
bash "${ROOT_DIR}/Scripts/install-on-device.sh" \
  --project Fake.xcodeproj \
  --scheme FakeScheme \
  --device-name MyDevice \
  --watch-name MyWatch \
  --watch-scheme FakeWatch

if ! rg -n "platform=iOS,name=MyDevice" "${XCODEBUILD_LOG}" >/dev/null; then
  echo "Expected xcodebuild destination by device name." >&2
  exit 1
fi

if ! rg -n "devicectl device install app --device MyDevice" "${XCRUN_LOG}" >/dev/null; then
  echo "Expected devicectl install by device name." >&2
  exit 1
fi

if ! rg -n "devicectl --timeout 240 device install app --device MyWatch" "${XCRUN_LOG}" >/dev/null; then
  echo "Expected watch install by device name." >&2
  exit 1
fi

if ! rg -n "devicectl device info apps --device MyDevice --bundle-id com.example.fake" "${XCRUN_LOG}" >/dev/null; then
  echo "Expected iOS verify by bundle id." >&2
  exit 1
fi

if ! rg -n "devicectl device info apps --device MyWatch --bundle-id com.example.fake.watch" "${XCRUN_LOG}" >/dev/null; then
  echo "Expected watch verify by bundle id." >&2
  exit 1
fi

echo "install-on-device.sh tests passed."
