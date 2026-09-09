#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source "${ROOT_DIR}/Scripts/lib/xcode-toolchain.sh"
source "${ROOT_DIR}/Scripts/lib/simulator-lifecycle.sh"
source "${ROOT_DIR}/Scripts/lib/logged-command.sh"

require_cmd() {
  local command_name="$1"
  local brew_formula="$2"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERRO: comando ausente: ${command_name}" >&2
    echo "Instale com: brew install ${brew_formula}" >&2
    exit 1
  fi
}

require_cmd rg ripgrep
require_cmd python3 python
aipedometer_select_xcode_26

STAMP="$(date +"%Y-%m-%d-%H%M%S")"
OUT_DIR="${E2E_OUT_DIR:-output/e2e-${STAMP}}"
DERIVED_DATA_ROOT="${E2E_DERIVED_DATA_ROOT:-${OUT_DIR}-DerivedData}"
IOS_DERIVED_DATA="${DERIVED_DATA_ROOT}/iOS"
WATCH_DERIVED_DATA="${DERIVED_DATA_ROOT}/watchOS"

IOS_UDID="${E2E_IOS_UDID:-}"
WATCH_UDID="${E2E_WATCH_UDID:-}"
ENABLE_WATCH="${E2E_ENABLE_WATCH:-1}"
ENABLE_WIDGETS="${E2E_ENABLE_WIDGETS:-1}"
ENABLE_SCREENSHOTS="${E2E_ENABLE_SCREENSHOTS:-1}"
ERASE_IOS_SIM="${E2E_ERASE_IOS_SIM:-0}"
ERASE_WATCH_SIM="${E2E_ERASE_WATCH_SIM:-0}"
SET_STATUS_BAR="${E2E_SET_STATUS_BAR:-0}"

if [[ "${E2E_IOS_DEST+x}" == "x" || "${E2E_WATCH_DEST+x}" == "x" ]]; then
  echo "ERRO: E2E_IOS_DEST e E2E_WATCH_DEST nao sao mais aceitos; use E2E_IOS_UDID e E2E_WATCH_UDID." >&2
  exit 2
fi

case "${ENABLE_WATCH}" in
  0) WATCH_UDID="" ;;
  1) ;;
  *) echo "ERRO: E2E_ENABLE_WATCH deve ser 0 ou 1." >&2; exit 2 ;;
esac

HOSTED_AUTO_SELECTION=0
if [[ "${GITHUB_ACTIONS:-}" == "true" && "${RUNNER_ENVIRONMENT:-}" == "github-hosted" ]]; then
  HOSTED_AUTO_SELECTION=1
fi

if [[ "${HOSTED_AUTO_SELECTION}" != "1" ]]; then
  if [[ -z "${IOS_UDID}" ]]; then
    echo "ERRO: defina E2E_IOS_UDID com o simulador iOS reservado para esta sessao." >&2
    exit 2
  fi
  if [[ "${ENABLE_WATCH}" == "1" && -z "${WATCH_UDID}" ]]; then
    echo "ERRO: defina E2E_WATCH_UDID quando E2E_ENABLE_WATCH=1." >&2
    exit 2
  fi
fi

SELECTION="$(
  xcrun simctl list devices --json |
    python3 -c '
import json
import sys

requested_ios, requested_watch, enable_watch_raw, hosted_raw = sys.argv[1:]
enable_watch = enable_watch_raw == "1"
hosted = hosted_raw == "1"

try:
    data = json.load(sys.stdin)
    devices = data["devices"]
    if not isinstance(devices, dict):
        raise TypeError
except (json.JSONDecodeError, KeyError, TypeError):
    raise SystemExit("ERRO: simctl retornou uma lista de devices invalida.")

def iter_devices():
    for runtime, devs in devices.items():
        if not isinstance(runtime, str) or not isinstance(devs, list):
            raise SystemExit("ERRO: simctl retornou uma lista de devices invalida.")
        for d in devs:
            if not isinstance(d, dict):
                raise SystemExit("ERRO: simctl retornou uma lista de devices invalida.")
            yield runtime, d

def runtime_family(runtime):
    leaf = runtime.rsplit(".", 1)[-1]
    if leaf.startswith("iOS-"):
        return "iOS"
    if leaf.startswith("watchOS-"):
        return "watchOS"
    return None

def runtime_sort_key(runtime):
    leaf = runtime.rsplit(".", 1)[-1]
    nums = [int(part) for part in leaf.split("-")[1:] if part.isdigit()]
    while len(nums) < 3:
        nums.append(0)
    return tuple(nums[:3])

def is_available(device):
    return device.get("isAvailable") is True and device.get("state") in ("Booted", "Shutdown")

def validate_udid(udid, family, label):
    matches = [(runtime, device) for runtime, device in iter_devices() if device.get("udid") == udid]
    if len(matches) != 1:
        raise SystemExit(f"ERRO: simulador {label} desconhecido.")
    runtime, device = matches[0]
    if runtime_family(runtime) != family:
        raise SystemExit(f"ERRO: simulador {label} nao pertence a familia {family}.")
    if not is_available(device):
        raise SystemExit(f"ERRO: simulador {label} indisponivel.")
    return udid

def pick_udid(family, name_prefixes):
    candidates = [
        (runtime, device)
        for runtime, device in iter_devices()
        if runtime_family(runtime) == family and is_available(device)
    ]
    candidates.sort(key=lambda x: runtime_sort_key(x[0]), reverse=True)
    for prefix in name_prefixes:
        for _, device in candidates:
            name = device.get("name")
            udid = device.get("udid")
            if isinstance(name, str) and name.startswith(prefix) and isinstance(udid, str) and udid:
                return udid
    raise SystemExit(f"ERRO: nenhum simulador {family} disponivel no runner hospedado.")

if requested_ios:
    ios_udid = validate_udid(requested_ios, "iOS", "iOS")
elif hosted:
    ios_udid = pick_udid("iOS", ("iPhone",))
else:
    raise SystemExit("ERRO: defina E2E_IOS_UDID com o simulador iOS reservado para esta sessao.")

watch_udid = ""
if enable_watch:
    if requested_watch:
        watch_udid = validate_udid(requested_watch, "watchOS", "watchOS")
    elif hosted:
        watch_udid = pick_udid("watchOS", ("Apple Watch SE", "Apple Watch Ultra", "Apple Watch Series", "Apple Watch"))
    else:
        raise SystemExit("ERRO: defina E2E_WATCH_UDID quando E2E_ENABLE_WATCH=1.")

print(f"{ios_udid}\t{watch_udid}")
' "${IOS_UDID}" "${WATCH_UDID}" "${ENABLE_WATCH}" "${HOSTED_AUTO_SELECTION}"
)"

IOS_UDID="${SELECTION%%$'\t'*}"
WATCH_UDID="${SELECTION#*$'\t'}"

IOS_DEST="platform=iOS Simulator,id=${IOS_UDID}"
WATCH_DEST="platform=watchOS Simulator,id=${WATCH_UDID}"

echo "Verificando entitlements..."
bash Scripts/verify-entitlements.sh

mkdir -p "${OUT_DIR}/screens"

echo "E2E (simulador) - saída: ${OUT_DIR}"
echo "DerivedData: ${DERIVED_DATA_ROOT}"
echo "iOS - destino: ${IOS_DEST}"
if [[ "${ENABLE_WATCH}" == "1" ]]; then
  echo "watchOS - destino: ${WATCH_DEST}"
else
  echo "watchOS - desativado (E2E_ENABLE_WATCH=${ENABLE_WATCH})"
  ERASE_WATCH_SIM="0"
fi

if [[ "${ERASE_IOS_SIM}" == "1" ]]; then
  echo "Limpando simulador iOS antes do boot final..."
fi
if [[ "${ENABLE_WATCH}" == "1" && "${ERASE_WATCH_SIM}" == "1" ]]; then
  echo "Limpando simulador watchOS antes do boot final..."
fi

aipedometer_prepare_simulator "${IOS_UDID}" "${ERASE_IOS_SIM}"
if [[ "${ENABLE_WATCH}" == "1" ]]; then
  aipedometer_prepare_simulator "${WATCH_UDID}" "${ERASE_WATCH_SIM}"
fi
open -a Simulator >/dev/null 2>&1 || true
sleep 2

echo "Build-for-testing (iOS)..."
aipedometer_run_logged "${OUT_DIR}/xcodebuild-build-for-testing.log" xcodebuild \
  -scheme AIPedometer \
  -destination "${IOS_DEST}" \
  -derivedDataPath "${IOS_DERIVED_DATA}" \
  -parallel-testing-enabled NO \
  build-for-testing

if [[ "${ENABLE_WIDGETS}" == "1" ]]; then
  echo "Verificando embed de widgets no app..."
  IOS_APP_PATH="${IOS_DERIVED_DATA}/Build/Products/Debug-iphonesimulator/AIPedometer.app"
  WIDGET_APPEX_PATH="${IOS_APP_PATH}/PlugIns/AIPedometerWidgets.appex"
  if [[ ! -d "${WIDGET_APPEX_PATH}" ]]; then
    echo "ERRO: widget extension nao esta embutido no app."
    echo "- esperado: ${WIDGET_APPEX_PATH}"
    echo "- dica: confira dependencias no project.yml (embed: true) e rode xcodegen generate"
    exit 1
  fi
fi

echo "Testes (unitários) (iOS)..."
UNIT_RESTART_MAX="${E2E_UNIT_RESTART_MAX:-3}"

run_unit_tests_once() {
  local attempt="$1"
  local log_file="${OUT_DIR}/xcodebuild-unit-tests-attempt-${attempt}.log"

  rm -rf "${OUT_DIR}/UnitTests.xcresult" >/dev/null 2>&1 || true

  aipedometer_run_logged "${log_file}" xcodebuild \
    -scheme AIPedometer \
    -destination "${IOS_DEST}" \
    -derivedDataPath "${IOS_DERIVED_DATA}" \
    -resultBundlePath "${OUT_DIR}/UnitTests.xcresult" \
    -parallel-testing-enabled NO \
    -collect-test-diagnostics on-failure \
    -only-testing:AIPedometerTests \
    test-without-building
  local status=$?

  cp -f "${log_file}" "${OUT_DIR}/xcodebuild-unit-tests.log" >/dev/null 2>&1 || true
  if [[ "${status}" -ne 0 ]]; then
    return "${status}"
  fi

  python3 Scripts/xcresult-summary.py \
    "${OUT_DIR}/UnitTests.xcresult" \
    --kind "Unit Tests" \
    --validate \
    >"${OUT_DIR}/unit-tests-summary.md"
}

unit_status=0
for attempt in $(seq 1 "${UNIT_RESTART_MAX}"); do
  set +e
  run_unit_tests_once "${attempt}"
  unit_status=$?
  set -e

  if [[ "${unit_status}" -eq 0 ]]; then
    break
  fi

  if bash Scripts/simulator-retry-classifier.sh "${OUT_DIR}/xcodebuild-unit-tests-attempt-${attempt}.log"; then
    echo "Unit tests falharam por instabilidade do simulador. Reiniciando e tentando novamente... (tentativa ${attempt}/${UNIT_RESTART_MAX})"
    xcrun simctl shutdown "${IOS_UDID}" >/dev/null 2>&1 || true
    sleep 2
    xcrun simctl boot "${IOS_UDID}" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "${IOS_UDID}" -b >/dev/null 2>&1 || true
    open -a Simulator >/dev/null 2>&1 || true
    sleep 3
    continue
  fi

  echo "Unit tests falharam (nao-recuperavel). Abortando."
  exit "${unit_status}"
done

if [[ "${unit_status}" -ne 0 ]]; then
  echo "Unit tests falharam apos ${UNIT_RESTART_MAX} tentativas."
  exit "${unit_status}"
fi

UI_TEST_ITERATIONS="${E2E_UI_TEST_ITERATIONS:-1}"

echo "Testes (UI/E2E) (iOS)... (iterações: ${UI_TEST_ITERATIONS})"

UI_RESTART_MAX="${E2E_UI_RESTART_MAX:-3}"

run_ui_tests_once() {
  local attempt="$1"
  local log_file="${OUT_DIR}/xcodebuild-ui-tests-attempt-${attempt}.log"

  rm -rf "${OUT_DIR}/UITests.xcresult" >/dev/null 2>&1 || true

  local status=0
  if [[ "${UI_TEST_ITERATIONS}" -gt 1 ]]; then
    aipedometer_run_logged "${log_file}" xcodebuild \
      -scheme AIPedometer \
      -destination "${IOS_DEST}" \
      -derivedDataPath "${IOS_DERIVED_DATA}" \
      -resultBundlePath "${OUT_DIR}/UITests.xcresult" \
      -parallel-testing-enabled NO \
      -collect-test-diagnostics on-failure \
      -test-iterations "${UI_TEST_ITERATIONS}" \
      -test-repetition-relaunch-enabled YES \
      -only-testing:AIPedometerUITests \
      test-without-building
    status=$?
  else
    aipedometer_run_logged "${log_file}" xcodebuild \
      -scheme AIPedometer \
      -destination "${IOS_DEST}" \
      -derivedDataPath "${IOS_DERIVED_DATA}" \
      -resultBundlePath "${OUT_DIR}/UITests.xcresult" \
      -parallel-testing-enabled NO \
      -collect-test-diagnostics on-failure \
      -only-testing:AIPedometerUITests \
      test-without-building
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

  python3 Scripts/xcresult-summary.py \
    "${OUT_DIR}/UITests.xcresult" \
    --kind "UI Tests" \
    --validate \
    >"${OUT_DIR}/ui-tests-summary.md"
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

  if bash Scripts/simulator-retry-classifier.sh "${OUT_DIR}/xcodebuild-ui-tests-attempt-${attempt}.log"; then
    echo "UI tests falharam por instabilidade do simulador. Reiniciando e tentando novamente... (tentativa ${attempt}/${UI_RESTART_MAX})"
    xcrun simctl shutdown "${IOS_UDID}" >/dev/null 2>&1 || true
    sleep 2
    xcrun simctl boot "${IOS_UDID}" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "${IOS_UDID}" -b >/dev/null 2>&1 || true
    open -a Simulator >/dev/null 2>&1 || true
    sleep 3
    continue
  fi

  echo "UI tests falharam (nao-recuperavel). Abortando."
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

if [[ "${ENABLE_WATCH}" == "1" ]]; then
  echo "Build (watchOS)..."
  aipedometer_run_logged "${OUT_DIR}/xcodebuild-watch-build.log" xcodebuild \
    -scheme AIPedometerWatch \
    -destination "${WATCH_DEST}" \
    -derivedDataPath "${WATCH_DERIVED_DATA}" \
    -parallel-testing-enabled NO \
    build
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
  cat "${OUT_DIR}/unit-tests-summary.md"
  cat "${OUT_DIR}/ui-tests-summary.md"
  echo "### Artefatos"
  echo
  echo "- Logs: \`${OUT_DIR}/*.log\`"
  echo "- Screenshots: \`${OUT_DIR}/screens/*.png\`"
  echo "- UI attachments exportados: \`${OUT_DIR}/screens/ui\`"
  echo "- UI screenshots (nomeados): \`${OUT_DIR}/screens/ui/named\`"
} >"${SUMMARY_FILE}"

echo "OK"
echo "- xcresult (unit): ${OUT_DIR}/UnitTests.xcresult"
echo "- xcresult (ui): ${OUT_DIR}/UITests.xcresult"
echo "- logs: ${OUT_DIR}/*.log"
echo "- screenshots: ${OUT_DIR}/screens/*.png"
echo "- summary: ${SUMMARY_FILE}"
