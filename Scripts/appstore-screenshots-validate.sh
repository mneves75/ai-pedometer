#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SCREENSHOTS_ROOT="${REPO_ROOT}/output/appstore-publishing/screenshots"

usage() {
  cat <<USAGE
Uso:
  bash Scripts/appstore-screenshots-validate.sh [opções]

Opções:
  --screenshots-root <dir>   Diretório raiz com subpastas iphone_65/ipad_13
                             (padrão: ${SCREENSHOTS_ROOT})
  -h, --help                 Mostra esta ajuda
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --screenshots-root)
      SCREENSHOTS_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Argumento inválido: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

assert_dir_has_pngs() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    echo "Diretório não encontrado: ${dir}" >&2
    return 1
  fi
  if ! find "${dir}" -maxdepth 1 -type f -name '*.png' | grep -q .; then
    echo "Nenhum PNG encontrado em: ${dir}" >&2
    return 1
  fi
}

check_dimensions() {
  local dir="$1"
  local expected_w="$2"
  local expected_h="$3"
  local label="$4"

  local failed=0
  local total=0

  while IFS= read -r -d '' file; do
    total=$((total + 1))
    local w h
    w="$(sips -g pixelWidth "${file}" | awk '/pixelWidth/ {print $2}')"
    h="$(sips -g pixelHeight "${file}" | awk '/pixelHeight/ {print $2}')"

    if [[ "${w}" != "${expected_w}" || "${h}" != "${expected_h}" ]]; then
      echo "[ERRO] ${label}: dimensão inválida em $(basename "${file}") => ${w}x${h} (esperado ${expected_w}x${expected_h})" >&2
      failed=1
    fi
  done < <(find "${dir}" -maxdepth 1 -type f -name '*.png' -print0 | sort -z)

  if [[ ${total} -eq 0 ]]; then
    echo "[ERRO] ${label}: sem arquivos" >&2
    return 1
  fi

  if [[ ${failed} -eq 0 ]]; then
    echo "[OK] ${label}: ${total} arquivo(s), todos em ${expected_w}x${expected_h}"
    return 0
  fi

  return 1
}

assert_dir_has_pngs "${SCREENSHOTS_ROOT}/iphone_65"
assert_dir_has_pngs "${SCREENSHOTS_ROOT}/ipad_13"

check_dimensions "${SCREENSHOTS_ROOT}/iphone_65" "1284" "2778" "iPhone 6.5"
check_dimensions "${SCREENSHOTS_ROOT}/ipad_13" "2064" "2752" "iPad Pro 12.9"

# Conjunto opcional (fonte capturada) para auditoria interna
if [[ -d "${SCREENSHOTS_ROOT}/iphone_69" ]] && find "${SCREENSHOTS_ROOT}/iphone_69" -maxdepth 1 -type f -name '*.png' | grep -q .; then
  check_dimensions "${SCREENSHOTS_ROOT}/iphone_69" "1320" "2868" "iPhone 6.9 (fonte)"
fi

echo "Validação concluída com sucesso."
