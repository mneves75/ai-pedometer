#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "${XCODEBUILD_LOG}"
if [[ "${1:-}" == "-version" ]]; then
  printf 'Xcode %s\nBuild version TEST\n' "${MOCK_XCODE_VERSION:-26.6}"
  exit 0
fi
if [[ "$*" == *"-showBuildSettings"* ]]; then
  # Real projects can emit hundreds of kilobytes here. Keep this fixture larger
  # than a pipe buffer so the installer cannot safely feed it through a here-string.
  for i in {1..5000}; do
    printf '    UNUSED_SETTING_%04d = padding-for-large-build-settings-output\n' "${i}"
  done
  if [[ "$*" == *"-scheme FakeWatch"* ]]; then
    cat <<SETTINGS
    BUILT_PRODUCTS_DIR = ${WATCH_PRODUCTS_DIR}
    FULL_PRODUCT_NAME = FakeWatch.app
    PRODUCT_BUNDLE_IDENTIFIER = com.example.fake.watch
SETTINGS
    exit 0
  fi
  cat <<SETTINGS
    BUILT_PRODUCTS_DIR = ${APP_PRODUCTS_DIR}
    FULL_PRODUCT_NAME = Fake.app
    PRODUCT_BUNDLE_IDENTIFIER = com.example.fake
SETTINGS
  exit 0
fi
if [[ "$*" == *"-scheme FakeWatch"* ]]; then
  mkdir -p "${WATCH_PRODUCTS_DIR}/FakeWatch.app"
  exit 0
fi
mkdir -p "${APP_PRODUCTS_DIR}/Fake.app"
exit 0
