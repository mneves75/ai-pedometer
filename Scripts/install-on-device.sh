#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERRO: comando ausente: $1" >&2
    exit 1
  fi
}

usage() {
  cat <<'EOF'
Uso:
  bash Scripts/install-on-device.sh [opcoes]

Opcoes:
  --device-name <nome>       Nome do device no Xcode (obrigatorio)
  --watch-name <nome>        Nome do Apple Watch para instalar o app watchOS (opcional)
  --watch-scheme <scheme>    Scheme watchOS (default: AIPedometerWatch)
  --build-retries <n>        Tentativas para operacoes de build (default: 2)
  --install-retries <n>      Tentativas para install/verify (default: 3)
  --retry-delay <seg>        Espera entre tentativas (default: 5)
  --destination-timeout <s>  Timeout de destino para xcodebuild (default: 120)
  --scheme <scheme>          Scheme do Xcode (default: AIPedometer)
  --project <caminho>        Projeto .xcodeproj (default: AIPedometer.xcodeproj)
  --configuration <nome>     Configuracao de build (default: Debug)
  --derived-data <caminho>   DerivedData customizado (opcional)
  --launch                   Faz launch do app apos instalar
  --help                     Mostra esta ajuda
EOF
}

DEVICE_NAME="${DEVICE_NAME:-}"
WATCH_NAME="${WATCH_NAME:-}"
WATCH_SCHEME="${WATCH_SCHEME:-AIPedometerWatch}"
SCHEME="${SCHEME:-AIPedometer}"
PROJECT_PATH="${PROJECT_PATH:-AIPedometer.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-}"
LAUNCH_AFTER_INSTALL="${LAUNCH_AFTER_INSTALL:-0}"
ALLOW_ENTITLEMENTS_MODIFICATION="${CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION:-YES}"
BUILD_RETRIES="${BUILD_RETRIES:-2}"
INSTALL_RETRIES="${INSTALL_RETRIES:-3}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-5}"
DESTINATION_TIMEOUT_SECONDS="${DESTINATION_TIMEOUT_SECONDS:-120}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-name)
      DEVICE_NAME="${2:-}"
      shift 2
      ;;
    --scheme)
      SCHEME="${2:-}"
      shift 2
      ;;
    --watch-name)
      WATCH_NAME="${2:-}"
      shift 2
      ;;
    --watch-scheme)
      WATCH_SCHEME="${2:-}"
      shift 2
      ;;
    --build-retries)
      BUILD_RETRIES="${2:-}"
      shift 2
      ;;
    --install-retries)
      INSTALL_RETRIES="${2:-}"
      shift 2
      ;;
    --retry-delay)
      RETRY_DELAY_SECONDS="${2:-}"
      shift 2
      ;;
    --destination-timeout)
      DESTINATION_TIMEOUT_SECONDS="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT_PATH="${2:-}"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --derived-data)
      DERIVED_DATA_PATH="${2:-}"
      shift 2
      ;;
    --launch)
      LAUNCH_AFTER_INSTALL="1"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERRO: opcao desconhecida: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${DEVICE_NAME}" ]]; then
  echo "ERRO: device vazio. Use --device-name." >&2
  exit 1
fi

if [[ ! "${INSTALL_RETRIES}" =~ ^[0-9]+$ ]] || (( INSTALL_RETRIES < 1 )); then
  echo "ERRO: --install-retries deve ser inteiro >= 1" >&2
  exit 1
fi

if [[ ! "${BUILD_RETRIES}" =~ ^[0-9]+$ ]] || (( BUILD_RETRIES < 1 )); then
  echo "ERRO: --build-retries deve ser inteiro >= 1" >&2
  exit 1
fi

if [[ ! "${RETRY_DELAY_SECONDS}" =~ ^[0-9]+$ ]] || (( RETRY_DELAY_SECONDS < 0 )); then
  echo "ERRO: --retry-delay deve ser inteiro >= 0" >&2
  exit 1
fi

if [[ ! "${DESTINATION_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || (( DESTINATION_TIMEOUT_SECONDS < 1 )); then
  echo "ERRO: --destination-timeout deve ser inteiro >= 1" >&2
  exit 1
fi

require_cmd xcodebuild
require_cmd xcrun

destination="platform=iOS,name=${DEVICE_NAME}"
ACTIVE_DEVELOPER_DIR="${DEVELOPER_DIR:-}"

run_xcodebuild() {
  if [[ -n "${ACTIVE_DEVELOPER_DIR}" ]]; then
    DEVELOPER_DIR="${ACTIVE_DEVELOPER_DIR}" xcodebuild "$@"
  else
    xcodebuild "$@"
  fi
}

run_xcrun() {
  if [[ -n "${ACTIVE_DEVELOPER_DIR}" ]]; then
    DEVELOPER_DIR="${ACTIVE_DEVELOPER_DIR}" xcrun "$@"
  else
    xcrun "$@"
  fi
}

run_build_with_fallback() {
  local -a args=("$@")
  local build_log

  build_log="$(mktemp -t aipedometer-install-build.XXXXXX.log)"
  if run_xcodebuild "${args[@]}" build 2>&1 | tee "${build_log}"; then
    return 0
  fi

  # Xcode 26.4 beta may report watchOS runtime as "missing" for embedded watch
  # schemes while stable Xcode builds/installs successfully on device.
  local stable_xcode_dir selected_xcode_dir
  stable_xcode_dir="/Applications/Xcode.app/Contents/Developer"
  selected_xcode_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ -z "${DEVELOPER_DIR:-}" \
    && -d "${stable_xcode_dir}" \
    && "${selected_xcode_dir}" != "${stable_xcode_dir}" ]] \
    && grep -Eq "embedded Apple Watch app\\. watchOS .* must be installed" "${build_log}"; then
    echo "==> Retry build com Xcode estavel: ${stable_xcode_dir}"
    ACTIVE_DEVELOPER_DIR="${stable_xcode_dir}"
    run_xcodebuild "${args[@]}" build
  else
    return 1
  fi
}

run_with_retries() {
  local max_attempts="$1"
  local delay_seconds="$2"
  local description="$3"
  shift 3
  local attempt=1

  while (( attempt <= max_attempts )); do
    if "$@"; then
      return 0
    fi

    if (( attempt == max_attempts )); then
      break
    fi

    echo "WARN: falha em '${description}' (tentativa ${attempt}/${max_attempts}). Retry em ${delay_seconds}s..."
    sleep "${delay_seconds}"
    ((attempt+=1))
  done

  echo "ERRO: '${description}' falhou apos ${max_attempts} tentativas." >&2
  return 1
}

verify_app_installed() {
  local device_name="$1"
  local bundle_id="$2"

  run_xcrun devicectl device info apps --device "${device_name}" --bundle-id "${bundle_id}" \
    | grep -Fq "${bundle_id}"
}

extract_target_setting() {
  local settings="$1"
  local target="$2"
  local key="$3"

  awk -v target="${target}" -v key="${key}" '
    $0 ~ ("^Build settings for action build and target " target ":") { in_target = 1; next }
    in_target && $0 ~ /^Build settings for action build and target / { in_target = 0 }
    in_target && $0 ~ ("^[[:space:]]*" key " = ") {
      sub("^[[:space:]]*" key " = ", "", $0)
      print
      exit
    }
  ' <<<"${settings}"
}

# ---------------------------------------------------------------------------
# Build on the selected physical iPhone destination.
# Do not force -sdk iphoneos because this scheme embeds a watch app and needs
# Xcode to resolve the correct SDKs per target.
# ---------------------------------------------------------------------------
xcodebuild_args=(
  -project "${PROJECT_PATH}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination "${destination}"
  -destination-timeout "${DESTINATION_TIMEOUT_SECONDS}"
  -allowProvisioningUpdates
  -allowProvisioningDeviceRegistration
  ONLY_ACTIVE_ARCH=YES
  CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION="${ALLOW_ENTITLEMENTS_MODIFICATION}"
)

# DEVELOPMENT_TEAM from environment overrides Local.xcconfig (CI use case)
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  xcodebuild_args+=(DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}")
fi

if [[ -n "${DERIVED_DATA_PATH}" ]]; then
  xcodebuild_args+=(-derivedDataPath "${DERIVED_DATA_PATH}")
fi

echo "==> Build (${CONFIGURATION}) para ${DEVICE_NAME}..."
if ! run_with_retries "${BUILD_RETRIES}" "${RETRY_DELAY_SECONDS}" "build iOS para ${DEVICE_NAME}" run_build_with_fallback "${xcodebuild_args[@]}"; then
  exit 1
fi

# ---------------------------------------------------------------------------
# Locate built .app via build settings
# ---------------------------------------------------------------------------
echo "==> Localizando .app..."
settings_args=(
  -project "${PROJECT_PATH}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination "${destination}"
  -destination-timeout "${DESTINATION_TIMEOUT_SECONDS}"
  -showBuildSettings
)
if [[ -n "${DERIVED_DATA_PATH}" ]]; then
  settings_args+=(-derivedDataPath "${DERIVED_DATA_PATH}")
fi

build_settings="$(run_xcodebuild "${settings_args[@]}" 2>/dev/null)"

built_products_dir="$(extract_target_setting "${build_settings}" "AIPedometer" "BUILT_PRODUCTS_DIR")"
full_product_name="$(extract_target_setting "${build_settings}" "AIPedometer" "FULL_PRODUCT_NAME")"
bundle_identifier="$(extract_target_setting "${build_settings}" "AIPedometer" "PRODUCT_BUNDLE_IDENTIFIER")"
if [[ -z "${built_products_dir}" || -z "${full_product_name}" ]]; then
  built_products_dir="$(awk -F ' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR = / { print $2; exit }' <<<"${build_settings}")"
  full_product_name="$(awk -F ' = ' '/^[[:space:]]*FULL_PRODUCT_NAME = / { print $2; exit }' <<<"${build_settings}")"
  bundle_identifier="$(awk -F ' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = / { print $2; exit }' <<<"${build_settings}")"
fi

app_path="${built_products_dir}/${full_product_name}"

if [[ ! -d "${app_path}" ]]; then
  echo "ERRO: app nao encontrada em ${app_path}" >&2
  exit 1
fi

# Verify watch app is embedded
if [[ -d "${app_path}/Watch" ]]; then
  echo "  Watch app embutido: $(ls "${app_path}/Watch/")"
fi

# ---------------------------------------------------------------------------
# Install on device via devicectl
# ---------------------------------------------------------------------------
echo "==> Instalando ${app_path} em ${DEVICE_NAME}..."
run_with_retries "${INSTALL_RETRIES}" "${RETRY_DELAY_SECONDS}" "install iOS app em ${DEVICE_NAME}" \
  run_xcrun devicectl device install app --device "${DEVICE_NAME}" "${app_path}"

if [[ "${LAUNCH_AFTER_INSTALL}" == "1" ]]; then
  if [[ -z "${bundle_identifier}" ]]; then
    echo "ERRO: PRODUCT_BUNDLE_IDENTIFIER vazio; nao foi possivel fazer launch." >&2
    exit 1
  fi

  echo "==> Fazendo launch de ${bundle_identifier}..."
  run_with_retries "${INSTALL_RETRIES}" "${RETRY_DELAY_SECONDS}" "launch iOS app em ${DEVICE_NAME}" \
    run_xcrun devicectl device process launch --device "${DEVICE_NAME}" "${bundle_identifier}" --activate
fi

echo "==> Verificando app iOS instalada..."
run_with_retries "${INSTALL_RETRIES}" "${RETRY_DELAY_SECONDS}" "verify iOS app em ${DEVICE_NAME}" \
  verify_app_installed "${DEVICE_NAME}" "${bundle_identifier}"

echo ""
echo "OK: instalado em ${DEVICE_NAME}"
if [[ -d "${app_path}/Watch" ]]; then
  echo "NOTA: O watch app sera transferido automaticamente para o Apple Watch pareado (~30-60s)."
fi

if [[ -n "${WATCH_NAME}" ]]; then
  watch_destination="platform=watchOS,name=${WATCH_NAME}"
  watch_build_args=(
    -project "${PROJECT_PATH}"
    -scheme "${WATCH_SCHEME}"
    -configuration "${CONFIGURATION}"
    -destination "${watch_destination}"
    -destination-timeout "${DESTINATION_TIMEOUT_SECONDS}"
    -allowProvisioningUpdates
    -allowProvisioningDeviceRegistration
    CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION="${ALLOW_ENTITLEMENTS_MODIFICATION}"
  )
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    watch_build_args+=(DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}")
  fi
  if [[ -n "${DERIVED_DATA_PATH}" ]]; then
    watch_build_args+=(-derivedDataPath "${DERIVED_DATA_PATH}")
  fi

  echo ""
  echo "==> Build watchOS (${CONFIGURATION}) para ${WATCH_NAME}..."
  watch_app_path=""
  watch_bundle_identifier=""
  if run_with_retries "${BUILD_RETRIES}" "${RETRY_DELAY_SECONDS}" "build watchOS para ${WATCH_NAME}" run_build_with_fallback "${watch_build_args[@]}"; then
    echo "==> Localizando .app do watch (saida de build watchOS)..."
    watch_settings_args=(
      -project "${PROJECT_PATH}"
      -scheme "${WATCH_SCHEME}"
      -configuration "${CONFIGURATION}"
      -destination "${watch_destination}"
      -destination-timeout "${DESTINATION_TIMEOUT_SECONDS}"
      -showBuildSettings
    )
    if [[ -n "${DERIVED_DATA_PATH}" ]]; then
      watch_settings_args+=(-derivedDataPath "${DERIVED_DATA_PATH}")
    fi
    watch_build_settings="$(run_xcodebuild "${watch_settings_args[@]}" 2>/dev/null)"
    watch_built_products_dir="$(extract_target_setting "${watch_build_settings}" "AIPedometerWatch" "BUILT_PRODUCTS_DIR")"
    watch_full_product_name="$(extract_target_setting "${watch_build_settings}" "AIPedometerWatch" "FULL_PRODUCT_NAME")"
    watch_bundle_identifier="$(extract_target_setting "${watch_build_settings}" "AIPedometerWatch" "PRODUCT_BUNDLE_IDENTIFIER")"
    if [[ -z "${watch_built_products_dir}" || -z "${watch_full_product_name}" ]]; then
      watch_built_products_dir="$(awk -F ' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR = / { print $2; exit }' <<<"${watch_build_settings}")"
      watch_full_product_name="$(awk -F ' = ' '/^[[:space:]]*FULL_PRODUCT_NAME = / { print $2; exit }' <<<"${watch_build_settings}")"
      watch_bundle_identifier="$(awk -F ' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = / { print $2; exit }' <<<"${watch_build_settings}")"
    fi
    watch_app_path="${watch_built_products_dir}/${watch_full_product_name}"
  else
    echo "WARN: build watchOS falhou; tentando fallback com app watch embutido no app iOS."
    fallback_watch_path="$(find "${app_path}/Watch" -maxdepth 1 -type d -name "*.app" | head -n 1)"
    if [[ -n "${fallback_watch_path}" ]]; then
      watch_app_path="${fallback_watch_path}"
      if [[ -f "${watch_app_path}/Info.plist" ]]; then
        watch_bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${watch_app_path}/Info.plist" 2>/dev/null || true)"
      fi
    fi
  fi

  if [[ -z "${watch_app_path}" || ! -d "${watch_app_path}" ]]; then
    echo "ERRO: app watch nao encontrada para instalar." >&2
    exit 1
  fi

  echo "==> Instalando ${watch_app_path} em ${WATCH_NAME}..."
  run_with_retries "${INSTALL_RETRIES}" "${RETRY_DELAY_SECONDS}" "install watch app em ${WATCH_NAME}" \
    run_xcrun devicectl --timeout 240 device install app --device "${WATCH_NAME}" "${watch_app_path}"

  if [[ -n "${watch_bundle_identifier}" ]]; then
    echo "==> Verificando instalacao do watch app..."
    run_with_retries "${INSTALL_RETRIES}" "${RETRY_DELAY_SECONDS}" "verify watch app em ${WATCH_NAME}" \
      verify_app_installed "${WATCH_NAME}" "${watch_bundle_identifier}"
    run_xcrun devicectl device info apps --device "${WATCH_NAME}" --bundle-id "${watch_bundle_identifier}" || true
  fi

  echo "OK: instalado no Apple Watch ${WATCH_NAME}"
fi
