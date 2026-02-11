#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Verificando entitlements..."
bash Scripts/verify-entitlements.sh

STAMP="$(date +"%Y-%m-%d-%H%M%S")"
OUT_DIR="${E2E_OUT_DIR:-output/e2e-${STAMP}}"
mkdir -p "${OUT_DIR}/screens"

IOS_UDID="${E2E_IOS_UDID:-}"
WATCH_UDID="${E2E_WATCH_UDID:-}"
ENABLE_WATCH="${E2E_ENABLE_WATCH:-1}"
ENABLE_WIDGETS="${E2E_ENABLE_WIDGETS:-1}"
ENABLE_SCREENSHOTS="${E2E_ENABLE_SCREENSHOTS:-1}"
ERASE_IOS_SIM="${E2E_ERASE_IOS_SIM:-0}"
ERASE_WATCH_SIM="${E2E_ERASE_WATCH_SIM:-0}"
SET_STATUS_BAR="${E2E_SET_STATUS_BAR:-0}"

if [[ "${ENABLE_WATCH}" != "1" ]]; then
  WATCH_UDID=""
fi

if [[ -z "${IOS_UDID}" || ( "${ENABLE_WATCH}" == "1" && -z "${WATCH_UDID}" ) ]]; then
  UDIDS="$(
    python3 - <<'PY'
import json
import os
import subprocess

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"], text=True))
devices = data.get("devices", {})
enable_watch = (os.environ.get("E2E_ENABLE_WATCH", "1") == "1")

def iter_devices():
    for runtime, devs in devices.items():
        for d in devs:
            yield runtime, d

def runtime_sort_key(runtime: str) -> tuple:
    # Example runtimes:
    # com.apple.CoreSimulator.SimRuntime.iOS-26-2
    # com.apple.CoreSimulator.SimRuntime.watchOS-26-2
    parts = runtime.split(".")[-1].split("-")
    if not parts:
        return (0, 0, 0)
    family = parts[0]
    nums = [int(p) for p in parts[1:] if p.isdigit()]
    while len(nums) < 3:
        nums.append(0)
    fam_rank = {"iOS": 3, "watchOS": 2}.get(family, 0)
    return (fam_rank, nums[0], nums[1])

def pick_udid(family: str, name_prefixes: tuple[str, ...]) -> str:
    # Prefer stability over "whatever is booted" for watchOS. New watch models
    # sometimes trigger noisy toolchain warnings (e.g. actool trait set).
    prefer_booted = (family != "watchOS")
    if prefer_booted:
        for prefix in name_prefixes:
            for runtime, d in iter_devices():
                if family not in runtime:
                    continue
                if d.get("state") != "Booted":
                    continue
                name = d.get("name", "")
                if name.startswith(prefix):
                    return d["udid"]

    # Otherwise pick the newest runtime and first matching device.
    candidates = [(runtime, d) for runtime, d in iter_devices() if family in runtime]
    candidates.sort(key=lambda x: runtime_sort_key(x[0]), reverse=True)
    for prefix in name_prefixes:
        for runtime, d in candidates:
            name = d.get("name", "")
            if name.startswith(prefix):
                return d["udid"]
    raise SystemExit(f"no simulator device found for {family}")

ios_udid = pick_udid("iOS", ("iPhone",))
watch_udid = ""
if enable_watch:
    try:
        watch_udid = pick_udid("watchOS", ("Apple Watch SE", "Apple Watch Ultra", "Apple Watch Series", "Apple Watch"))
    except SystemExit:
        watch_udid = ""
print(f"{ios_udid} {watch_udid}")
PY
  )"

  IOS_UDID="${IOS_UDID:-${UDIDS%% *}}"
  WATCH_UDID="${WATCH_UDID:-${UDIDS#* }}"
fi

IOS_DEST="platform=iOS Simulator,id=${IOS_UDID}"
WATCH_DEST="platform=watchOS Simulator,id=${WATCH_UDID}"

IOS_DEST="${E2E_IOS_DEST:-$IOS_DEST}"
WATCH_DEST="${E2E_WATCH_DEST:-$WATCH_DEST}"

echo "E2E (simulador) - saída: ${OUT_DIR}"
echo "iOS - destino: ${IOS_DEST}"
if [[ "${ENABLE_WATCH}" == "1" && -n "${WATCH_UDID}" ]]; then
  echo "watchOS - destino: ${WATCH_DEST}"
else
  echo "watchOS - desativado (E2E_ENABLE_WATCH=${ENABLE_WATCH})"
  ENABLE_WATCH="0"
  ERASE_WATCH_SIM="0"
fi

if [[ -n "${IOS_UDID}" ]]; then
  # Proactively boot and wait for a stable simulator state before running tests.
  xcrun simctl boot "${IOS_UDID}" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "${IOS_UDID}" -b >/dev/null 2>&1 || true
  open -a Simulator >/dev/null 2>&1 || true
  sleep 2
fi

if [[ "${ERASE_IOS_SIM}" == "1" ]]; then
  echo "Limpando simulador iOS (shutdown + erase)..."
  xcrun simctl shutdown "${IOS_UDID}" >/dev/null 2>&1 || true
  xcrun simctl erase "${IOS_UDID}" >/dev/null 2>&1 || true
fi
if [[ "${ENABLE_WATCH}" == "1" && "${ERASE_WATCH_SIM}" == "1" ]]; then
  echo "Limpando simulador watchOS (shutdown + erase)..."
  xcrun simctl shutdown "${WATCH_UDID}" >/dev/null 2>&1 || true
  xcrun simctl erase "${WATCH_UDID}" >/dev/null 2>&1 || true
fi

xcrun simctl boot "${IOS_UDID}" >/dev/null 2>&1 || true
if [[ "${ENABLE_WATCH}" == "1" ]]; then
  xcrun simctl boot "${WATCH_UDID}" >/dev/null 2>&1 || true
fi
open -a Simulator >/dev/null 2>&1 || true

echo "Build-for-testing (iOS)..."
xcodebuild \
  -scheme AIPedometer \
  -destination "${IOS_DEST}" \
  -derivedDataPath "${OUT_DIR}/DerivedData-iOS" \
  -parallel-testing-enabled NO \
  build-for-testing \
  | tee "${OUT_DIR}/xcodebuild-build-for-testing.log"

if [[ "${ENABLE_WIDGETS}" == "1" ]]; then
  echo "Verificando embed de widgets no app..."
  IOS_APP_PATH="${OUT_DIR}/DerivedData-iOS/Build/Products/Debug-iphonesimulator/AIPedometer.app"
  WIDGET_APPEX_PATH="${IOS_APP_PATH}/PlugIns/AIPedometerWidgets.appex"
  if [[ ! -d "${WIDGET_APPEX_PATH}" ]]; then
    echo "ERRO: widget extension nao esta embutido no app."
    echo "- esperado: ${WIDGET_APPEX_PATH}"
    echo "- dica: confira dependencias no project.yml (embed: true) e rode xcodegen generate"
    exit 1
  fi
fi

echo "Testes (unitários) (iOS)..."
xcodebuild \
  -scheme AIPedometer \
  -destination "${IOS_DEST}" \
  -derivedDataPath "${OUT_DIR}/DerivedData-iOS" \
  -resultBundlePath "${OUT_DIR}/UnitTests.xcresult" \
  -parallel-testing-enabled NO \
  -collect-test-diagnostics on-failure \
  -only-testing:AIPedometerTests \
  test-without-building \
  | tee "${OUT_DIR}/xcodebuild-unit-tests.log"

UI_TEST_ITERATIONS="${E2E_UI_TEST_ITERATIONS:-1}"

echo "Testes (UI/E2E) (iOS)... (iterações: ${UI_TEST_ITERATIONS})"

UI_RESTART_MAX="${E2E_UI_RESTART_MAX:-3}"

run_ui_tests_once() {
  local attempt="$1"
  local log_file="${OUT_DIR}/xcodebuild-ui-tests-attempt-${attempt}.log"

  rm -rf "${OUT_DIR}/UITests.xcresult" >/dev/null 2>&1 || true

  local status=0
  if [[ "${UI_TEST_ITERATIONS}" -gt 1 ]]; then
    xcodebuild \
      -scheme AIPedometer \
      -destination "${IOS_DEST}" \
      -derivedDataPath "${OUT_DIR}/DerivedData-iOS" \
      -resultBundlePath "${OUT_DIR}/UITests.xcresult" \
      -parallel-testing-enabled NO \
      -collect-test-diagnostics on-failure \
      -test-iterations "${UI_TEST_ITERATIONS}" \
      -test-repetition-relaunch-enabled YES \
      -only-testing:AIPedometerUITests \
      test-without-building \
      | tee "${log_file}"
    status=$?
  else
    xcodebuild \
      -scheme AIPedometer \
      -destination "${IOS_DEST}" \
      -derivedDataPath "${OUT_DIR}/DerivedData-iOS" \
      -resultBundlePath "${OUT_DIR}/UITests.xcresult" \
      -parallel-testing-enabled NO \
      -collect-test-diagnostics on-failure \
      -only-testing:AIPedometerUITests \
      test-without-building \
      | tee "${log_file}"
    status=$?
  fi

  cp -f "${log_file}" "${OUT_DIR}/xcodebuild-ui-tests.log" >/dev/null 2>&1 || true

  # Defensive: in some toolchain states, xcodebuild may print "TEST EXECUTE FAILED"
  # but still exit 0. Treat that as a failure so we can reboot/retry cleanly.
  if [[ "${status}" -ne 0 ]]; then
    return "${status}"
  fi
  if rg -n "\\*\\* TEST EXECUTE FAILED \\*\\*" "${log_file}" >/dev/null 2>&1; then
    return 1
  fi
}

ui_status=0
for attempt in $(seq 1 "${UI_RESTART_MAX}"); do
  set +e
  run_ui_tests_once "${attempt}"
  ui_status=$?
  set -e

  if [[ "${ui_status}" -eq 0 ]]; then
    break
  fi

  if rg -n "Timed out waiting for AX loaded notification|Failed to initialize for UI testing|AX loaded notification|kAXErrorAPIDisabled|Failed to get matching snapshots" "${OUT_DIR}/xcodebuild-ui-tests-attempt-${attempt}.log" >/dev/null 2>&1; then
    echo "UI tests falharam ao inicializar (AX). Reiniciando o simulador e tentando novamente... (tentativa ${attempt}/${UI_RESTART_MAX})"
    xcrun simctl shutdown "${IOS_UDID}" >/dev/null 2>&1 || true
    sleep 2
    xcrun simctl boot "${IOS_UDID}" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "${IOS_UDID}" -b >/dev/null 2>&1 || true
    open -a Simulator >/dev/null 2>&1 || true
    sleep 3
    continue
  fi

  echo "UI tests falharam (nao-AX). Abortando."
  exit "${ui_status}"
done

if [[ "${ui_status}" -ne 0 ]]; then
  echo "UI tests falharam apos ${UI_RESTART_MAX} tentativas."
  exit "${ui_status}"
fi

echo "Exportando attachments do .xcresult (UI)..."
mkdir -p "${OUT_DIR}/screens/ui"
xcrun xcresulttool export attachments \
  --path "${OUT_DIR}/UITests.xcresult" \
  --output-path "${OUT_DIR}/screens/ui" \
  >/dev/null 2>&1 || true

python3 - "${OUT_DIR}" <<'PY' || true
import json
import re
import shutil
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
ui_dir = out_dir / "screens" / "ui"
manifest_path = ui_dir / "manifest.json"
named_dir = ui_dir / "named"
named_dir.mkdir(parents=True, exist_ok=True)

if not manifest_path.exists():
    raise SystemExit(0)

manifest = json.loads(manifest_path.read_text())
if not isinstance(manifest, list):
    raise SystemExit(0)

def safe_filename(name: str) -> str:
    # Keep mostly-human names, but make them shell/FS-safe and consistent.
    name = name.strip()
    name = re.sub(r"[\r\n\t]", " ", name)
    name = name.replace("/", "_")
    name = re.sub(r"\\s+", " ", name)
    return name

for entry in manifest:
    attachments = entry.get("attachments") or []
    for a in attachments:
        exported = a.get("exportedFileName")
        suggested = a.get("suggestedHumanReadableName")
        if not exported or not suggested:
            continue
        src = ui_dir / exported
        if not src.exists():
            continue
        dst = named_dir / safe_filename(suggested)
        # Copy (not symlink) so archives are portable.
        shutil.copyfile(src, dst)
PY

if [[ "${ENABLE_WIDGETS}" == "1" ]]; then
  echo "Build (widgets)..."
  xcodebuild \
    -project AIPedometer.xcodeproj \
    -target AIPedometerWidgets \
    -sdk iphonesimulator \
    -parallel-testing-enabled NO \
    SYMROOT="${OUT_DIR}/Build-widgets" \
    OBJROOT="${OUT_DIR}/Build-widgets-obj" \
    build \
    | tee "${OUT_DIR}/xcodebuild-widgets-build.log"
else
  echo "Build (widgets) - pulado (E2E_ENABLE_WIDGETS=${ENABLE_WIDGETS})"
fi

if [[ "${ENABLE_WATCH}" == "1" ]]; then
  echo "Build (watchOS)..."
  xcodebuild \
    -scheme AIPedometerWatch \
    -destination "${WATCH_DEST}" \
    -derivedDataPath "${OUT_DIR}/DerivedData-watch" \
    -parallel-testing-enabled NO \
    build \
    | tee "${OUT_DIR}/xcodebuild-watch-build.log"
fi

if [[ "${ENABLE_SCREENSHOTS}" == "1" ]]; then
  echo "Abrindo apps e tirando screenshots..."
  IOS_BUNDLE_ID="com.mneves.aipedometer"
  WATCH_BUNDLE_ID="com.mneves.aipedometer.watch"

  if [[ "${SET_STATUS_BAR}" == "1" ]]; then
    xcrun simctl status_bar "${IOS_UDID}" override \
      --time "09:41" \
      --wifiBars 3 \
      --cellularBars 4 \
      --batteryState charged \
      --batteryLevel 100 >/dev/null 2>&1 || true
  fi

  xcrun simctl launch "${IOS_UDID}" "${IOS_BUNDLE_ID}" >/dev/null 2>&1 || true
  xcrun simctl io "${IOS_UDID}" screenshot "${OUT_DIR}/screens/ios.png" >/dev/null 2>&1 || true

  if [[ "${ENABLE_WATCH}" == "1" ]]; then
    xcrun simctl launch "${WATCH_UDID}" "${WATCH_BUNDLE_ID}" >/dev/null 2>&1 || true
    xcrun simctl io "${WATCH_UDID}" screenshot "${OUT_DIR}/screens/watch.png" >/dev/null 2>&1 || true
  fi

  if [[ "${SET_STATUS_BAR}" == "1" ]]; then
    xcrun simctl status_bar "${IOS_UDID}" clear >/dev/null 2>&1 || true
  fi
fi

SUMMARY_FILE="${OUT_DIR}/summary.md"
{
  echo "# E2E (Simulador) - Resumo"
  echo
  python3 Scripts/xcresult-summary.py "${OUT_DIR}/UnitTests.xcresult" --kind "Unit Tests"
  python3 Scripts/xcresult-summary.py "${OUT_DIR}/UITests.xcresult" --kind "UI Tests"
  echo "### Artefatos"
  echo
  echo "- Logs: \`${OUT_DIR}/*.log\`"
  echo "- Screenshots: \`${OUT_DIR}/screens/*.png\`"
  echo "- UI attachments exportados: \`${OUT_DIR}/screens/ui\`"
  echo "- UI screenshots (nomeados): \`${OUT_DIR}/screens/ui/named\`"
} >"${SUMMARY_FILE}" || true

echo "OK"
echo "- xcresult (unit): ${OUT_DIR}/UnitTests.xcresult"
echo "- xcresult (ui): ${OUT_DIR}/UITests.xcresult"
echo "- logs: ${OUT_DIR}/*.log"
echo "- screenshots: ${OUT_DIR}/screens/*.png"
echo "- summary: ${SUMMARY_FILE}"
