#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SCREENSHOTS_ROOT="${REPO_ROOT}/output/appstore-publishing/screenshots"
VERSION_LOCALIZATION_ID=""
APP_ID=""
VERSION_STRING=""
LOCALE="pt-BR"
DRY_RUN=0

usage() {
  cat <<USAGE
Uso:
  bash Scripts/appstore-screenshots-upload.sh [opções]

Fluxo A (direto):
  --version-localization-id <id>

Fluxo B (resolver ID automaticamente):
  --app-id <id> --version <semver> --locale <locale>

Opções:
  --screenshots-root <dir>        Diretório raiz com iphone_65/ipad_13
                                  (padrão: ${SCREENSHOTS_ROOT})
  --version-localization-id <id>  ID de localização da versão (ASC)
  --app-id <id>                   App ID do ASC (usado para resolver automaticamente)
  --version <valor>               Versão (ex.: 0.7)
  --locale <locale>               Localização (ex.: pt-BR, en-US). Padrão: pt-BR
  --dry-run                       Só imprime os comandos
  -h, --help                      Mostra ajuda
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --screenshots-root)
      SCREENSHOTS_ROOT="$2"
      shift 2
      ;;
    --version-localization-id)
      VERSION_LOCALIZATION_ID="$2"
      shift 2
      ;;
    --app-id)
      APP_ID="$2"
      shift 2
      ;;
    --version)
      VERSION_STRING="$2"
      shift 2
      ;;
    --locale)
      LOCALE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
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

if [[ ! -d "${SCREENSHOTS_ROOT}/iphone_65" || ! -d "${SCREENSHOTS_ROOT}/ipad_13" ]]; then
  echo "Conjunto de screenshots não encontrado em ${SCREENSHOTS_ROOT}." >&2
  echo "Execute antes: bash Scripts/appstore-materials-prepare.sh" >&2
  exit 1
fi

resolve_version_localization_id() {
  if [[ -n "${VERSION_LOCALIZATION_ID}" ]]; then
    return 0
  fi

  if [[ -z "${APP_ID}" || -z "${VERSION_STRING}" ]]; then
    echo "Forneça --version-localization-id ou (--app-id e --version)." >&2
    return 1
  fi

  local versions_json
  versions_json="$(asc versions list --app "${APP_ID}" --platform IOS --version "${VERSION_STRING}" --output json)"

  local version_id
  version_id="$(python3 - <<'PY' "$versions_json"
import json,sys
obj=json.loads(sys.argv[1])
data=obj.get('data',[])
print(data[0]['id'] if data else '')
PY
)"

  if [[ -z "${version_id}" ]]; then
    echo "Não encontrei versão ${VERSION_STRING} no app ${APP_ID}." >&2
    return 1
  fi

  local loc_json
  loc_json="$(asc localizations list --version "${version_id}" --locale "${LOCALE}" --output json)"

  VERSION_LOCALIZATION_ID="$(python3 - <<'PY' "$loc_json"
import json,sys
obj=json.loads(sys.argv[1])
data=obj.get('data',[])
print(data[0]['id'] if data else '')
PY
)"

  if [[ -z "${VERSION_LOCALIZATION_ID}" ]]; then
    echo "Não encontrei localization para locale=${LOCALE} na versão ${VERSION_STRING}." >&2
    return 1
  fi

  echo "Localization resolvida automaticamente: ${VERSION_LOCALIZATION_ID} (locale=${LOCALE})"
}

run_or_echo() {
  if [[ ${DRY_RUN} -eq 1 ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi

  "$@"
}

resolve_version_localization_id

run_or_echo asc screenshots upload \
  --version-localization "${VERSION_LOCALIZATION_ID}" \
  --path "${SCREENSHOTS_ROOT}/iphone_65" \
  --device-type "IPHONE_65" \
  --output table

run_or_echo asc screenshots upload \
  --version-localization "${VERSION_LOCALIZATION_ID}" \
  --path "${SCREENSHOTS_ROOT}/ipad_13" \
  --device-type "IPAD_PRO_3GEN_129" \
  --output table

echo "Upload concluído."
