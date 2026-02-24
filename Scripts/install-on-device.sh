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
  --device-name <nome>       Nome do device no Xcode (obrigatório)
  --scheme <scheme>          Scheme do Xcode (default: AIPedometer)
  --project <caminho>        Projeto .xcodeproj (default: AIPedometer.xcodeproj)
  --configuration <nome>     Configuracao de build (default: Debug)
  --derived-data <caminho>   DerivedData customizado (opcional)
  --launch                   Faz launch do app apos instalar
  --help                     Mostra esta ajuda
EOF
}

DEVICE_NAME="${DEVICE_NAME:-}"
SCHEME="${SCHEME:-AIPedometer}"
PROJECT_PATH="${PROJECT_PATH:-AIPedometer.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-}"
LAUNCH_AFTER_INSTALL="${LAUNCH_AFTER_INSTALL:-0}"

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

require_cmd xcodebuild
require_cmd xcrun

destination="platform=iOS,name=${DEVICE_NAME}"
xcodebuild_args=(
  -project "${PROJECT_PATH}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination "${destination}"
)

if [[ -n "${DERIVED_DATA_PATH}" ]]; then
  xcodebuild_args+=(-derivedDataPath "${DERIVED_DATA_PATH}")
fi

echo "==> Lendo build settings para ${SCHEME} em ${DEVICE_NAME}..."
build_settings="$(xcodebuild "${xcodebuild_args[@]}" -showBuildSettings)"

built_products_dir="$(awk -F ' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR = / { print $2; exit }' <<<"${build_settings}")"
full_product_name="$(awk -F ' = ' '/^[[:space:]]*FULL_PRODUCT_NAME = / { print $2; exit }' <<<"${build_settings}")"
bundle_identifier="$(awk -F ' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = / { print $2; exit }' <<<"${build_settings}")"

if [[ -z "${built_products_dir}" || -z "${full_product_name}" ]]; then
  echo "ERRO: nao foi possivel resolver caminho do .app via build settings." >&2
  exit 1
fi

app_path="${built_products_dir}/${full_product_name}"

echo "==> Build (${CONFIGURATION}) para ${DEVICE_NAME}..."
xcodebuild "${xcodebuild_args[@]}" build

if [[ ! -d "${app_path}" ]]; then
  echo "ERRO: app nao encontrada em ${app_path}" >&2
  exit 1
fi

echo "==> Instalando ${app_path} em ${DEVICE_NAME}..."
xcrun devicectl device install app --device "${DEVICE_NAME}" "${app_path}"

if [[ "${LAUNCH_AFTER_INSTALL}" == "1" ]]; then
  if [[ -z "${bundle_identifier}" ]]; then
    echo "ERRO: PRODUCT_BUNDLE_IDENTIFIER vazio; nao foi possivel fazer launch." >&2
    exit 1
  fi

  echo "==> Fazendo launch de ${bundle_identifier}..."
  xcrun devicectl device process launch --device "${DEVICE_NAME}" "${bundle_identifier}" --activate
fi

echo "OK: instalado em ${DEVICE_NAME}"
