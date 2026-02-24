#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${FAKE_BIN}"

XCODEBUILD_LOG="${TMP_DIR}/xcodebuild.log"
XCRUN_LOG="${TMP_DIR}/xcrun.log"
APP_DIR="${TMP_DIR}/DerivedData/Build/Products/Debug-iphoneos/Fake.app"
mkdir -p "$(dirname "${APP_DIR}")"

cat > "${FAKE_BIN}/xcodebuild" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "${XCODEBUILD_LOG}"
if [[ "$*" == *"-showBuildSettings"* ]]; then
  cat <<SETTINGS
    BUILT_PRODUCTS_DIR = ${APP_PRODUCTS_DIR}
    FULL_PRODUCT_NAME = Fake.app
    PRODUCT_BUNDLE_IDENTIFIER = com.example.fake
SETTINGS
  exit 0
fi
mkdir -p "${APP_PRODUCTS_DIR}/Fake.app"
exit 0
EOF

cat > "${FAKE_BIN}/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "${XCRUN_LOG}"
exit 0
EOF

chmod +x "${FAKE_BIN}/xcodebuild" "${FAKE_BIN}/xcrun"

PATH="${FAKE_BIN}:${PATH}" \
XCODEBUILD_LOG="${XCODEBUILD_LOG}" \
XCRUN_LOG="${XCRUN_LOG}" \
APP_PRODUCTS_DIR="$(dirname "${APP_DIR}")" \
bash "${ROOT_DIR}/Scripts/install-on-device.sh" \
  --project Fake.xcodeproj \
  --scheme FakeScheme \
  --device-name MyDevice

if ! rg -n "platform=iOS,name=MyDevice" "${XCODEBUILD_LOG}" >/dev/null; then
  echo "Expected xcodebuild destination by device name." >&2
  exit 1
fi

if ! rg -n "devicectl device install app --device MyDevice" "${XCRUN_LOG}" >/dev/null; then
  echo "Expected devicectl install by device name." >&2
  exit 1
fi

echo "install-on-device.sh tests passed."
