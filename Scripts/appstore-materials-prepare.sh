#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IPHONE_SRC_DEFAULT="${REPO_ROOT}/output/appstore-capture-iphone/screens/ui/named"
IPAD_SRC_DEFAULT="${REPO_ROOT}/output/appstore-capture-ipad/screens/onboarding/named"
OUT_DIR_DEFAULT="${REPO_ROOT}/output/appstore-publishing"

IPHONE_SRC="${IPHONE_SRC_DEFAULT}"
IPAD_SRC="${IPAD_SRC_DEFAULT}"
OUT_DIR="${OUT_DIR_DEFAULT}"

usage() {
  cat <<USAGE
Uso:
  bash Scripts/appstore-materials-prepare.sh [opções]

Opções:
  --iphone-src <dir>    Diretório com screenshots nomeadas do iPhone
                        (padrão: ${IPHONE_SRC_DEFAULT})
  --ipad-src <dir>      Diretório com screenshots nomeadas do iPad
                        (padrão: ${IPAD_SRC_DEFAULT})
  --out-dir <dir>       Diretório de saída final
                        (padrão: ${OUT_DIR_DEFAULT})
  -h, --help            Mostra esta ajuda

Saída:
  <out-dir>/screenshots/iphone_69   (1320x2868, base capturada)
  <out-dir>/screenshots/iphone_65   (1284x2778, pronto para upload)
  <out-dir>/screenshots/ipad_13     (2064x2752, pronto para upload)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iphone-src)
      IPHONE_SRC="$2"
      shift 2
      ;;
    --ipad-src)
      IPAD_SRC="$2"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="$2"
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

if [[ ! -d "${IPHONE_SRC}" ]]; then
  echo "Diretório de screenshots iPhone não encontrado: ${IPHONE_SRC}" >&2
  exit 1
fi

if [[ ! -d "${IPAD_SRC}" ]]; then
  echo "Diretório de screenshots iPad não encontrado: ${IPAD_SRC}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}/screenshots/iphone_69" "${OUT_DIR}/screenshots/iphone_65" "${OUT_DIR}/screenshots/ipad_13"

rm -f "${OUT_DIR}/screenshots/iphone_69"/*.png "${OUT_DIR}/screenshots/iphone_65"/*.png "${OUT_DIR}/screenshots/ipad_13"/*.png

iphone_prefixes=(
  "Dashboard"
  "AI Coach"
  "Workouts"
  "Training Plans"
  "History"
  "Badges"
  "Active Workout"
  "About - Tip Jar"
)

ipad_prefixes=(
  "Onboarding - Welcome"
  "Onboarding - Goal"
  "Onboarding - Permissions"
)

find_one_by_prefix() {
  local dir="$1"
  local prefix="$2"

  shopt -s nullglob
  local matches=("${dir}/${prefix}_"*.png)
  shopt -u nullglob

  if [[ ${#matches[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${matches[0]}"
  return 0
}

copy_ordered_set() {
  local src_dir="$1"
  local dest_dir="$2"
  shift 2

  local index=1
  local src_file=""
  local filename=""
  local prefix=""

  for prefix in "$@"; do
    if ! src_file="$(find_one_by_prefix "${src_dir}" "${prefix}")"; then
      echo "Screenshot não encontrada para prefixo: ${prefix}" >&2
      return 1
    fi

    filename="$(printf '%02d-%s.png' "${index}" "$(echo "${prefix}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')")"
    cp "${src_file}" "${dest_dir}/${filename}"
    index=$((index + 1))
  done
}

copy_ordered_set "${IPHONE_SRC}" "${OUT_DIR}/screenshots/iphone_69" "${iphone_prefixes[@]}"
copy_ordered_set "${IPAD_SRC}" "${OUT_DIR}/screenshots/ipad_13" "${ipad_prefixes[@]}"

for file in "${OUT_DIR}"/screenshots/iphone_69/*.png; do
  base="$(basename "${file}")"
  cp "${file}" "${OUT_DIR}/screenshots/iphone_65/${base}"
  # sips -z recebe altura largura
  sips -z 2778 1284 "${OUT_DIR}/screenshots/iphone_65/${base}" >/dev/null
done

{
  echo "# App Store Screenshot Package"
  echo
  echo "Gerado em: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo ""
  echo "## Conjuntos"
  echo "- iphone_69: fonte original (1320x2868)"
  echo "- iphone_65: pronto para upload (1284x2778)"
  echo "- ipad_13: pronto para upload (2064x2752)"
  echo ""
  echo "## Arquivos"
  find "${OUT_DIR}/screenshots" -type f -name '*.png' | sort | sed "s#${OUT_DIR}/##"
} > "${OUT_DIR}/README.md"

echo "Pacote preparado em: ${OUT_DIR}"
echo "Execute validação: bash Scripts/appstore-screenshots-validate.sh --screenshots-root ${OUT_DIR}/screenshots"
