#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUT_DIR="${REPO_ROOT}/output/appstore-publishing"
RUN_UPLOAD_DRY_RUN=0
VERSION_LOCALIZATION_ID=""
APP_ID=""
VERSION_STRING=""
LOCALE="pt-BR"

usage() {
  cat <<USAGE
Uso:
  bash Scripts/appstore-publishing-preflight.sh [opções]

Opções:
  --out-dir <dir>                  Diretório de saída do pacote
                                   (padrão: ${OUT_DIR})
  --run-upload-dry-run             Executa upload em dry-run no final
  --version-localization-id <id>   Localization ID (se usar --run-upload-dry-run)
  --app-id <id>                    App ID ASC (resolver localization automaticamente)
  --version <semver>               Versão da app (ex.: 0.7)
  --locale <locale>                Locale para resolver localization (padrão: pt-BR)
  -h, --help                       Mostra ajuda
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --run-upload-dry-run)
      RUN_UPLOAD_DRY_RUN=1
      shift
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

echo "==> [1/4] Matriz de screenshots ASC"
asc screenshots sizes --output table

echo "==> [2/4] Preparando pacote"
bash "${REPO_ROOT}/Scripts/appstore-materials-prepare.sh" --out-dir "${OUT_DIR}"

echo "==> [3/4] Validando pacote"
bash "${REPO_ROOT}/Scripts/appstore-screenshots-validate.sh" --screenshots-root "${OUT_DIR}/screenshots"

echo "==> [4/4] Checagem de metadata templates"
if rg -n "<preencher>|<fill>" "${REPO_ROOT}/docs/appstore/metadata" -S >/dev/null; then
  echo "[AVISO] Templates de metadata ainda possuem placeholders (<preencher>/<fill>)."
  echo "        Preencha antes da submissão final."
else
  echo "[OK] Metadata templates sem placeholders."
fi

if [[ ${RUN_UPLOAD_DRY_RUN} -eq 1 ]]; then
  echo "==> Upload dry-run"
  UPLOAD_ARGS=(--screenshots-root "${OUT_DIR}/screenshots" --dry-run --locale "${LOCALE}")

  if [[ -n "${VERSION_LOCALIZATION_ID}" ]]; then
    UPLOAD_ARGS+=(--version-localization-id "${VERSION_LOCALIZATION_ID}")
  fi

  if [[ -n "${APP_ID}" ]]; then
    UPLOAD_ARGS+=(--app-id "${APP_ID}")
  fi

  if [[ -n "${VERSION_STRING}" ]]; then
    UPLOAD_ARGS+=(--version "${VERSION_STRING}")
  fi

  bash "${REPO_ROOT}/Scripts/appstore-screenshots-upload.sh" "${UPLOAD_ARGS[@]}"
fi

echo "Preflight concluído."
