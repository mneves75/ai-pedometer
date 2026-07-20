#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "${ROOT_DIR}/Scripts/lib/xcode-toolchain.sh"

bash "${ROOT_DIR}/Scripts/verify-device-identifiers.sh"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERRO: comando ausente: $1"
    exit 1
  fi
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERRO: variavel de ambiente obrigatoria nao definida: ${name}"
    exit 1
  fi
}

redact_sensitive_output() {
  AIPEDOMETER_REDACT_APP_ID="${APP_ID:-}" \
    AIPEDOMETER_REDACT_GROUP_ID="${GROUP_ID:-}" \
    AIPEDOMETER_REDACT_ROOT_DIR="${ROOT_DIR}" \
    python3 -c '
import os
import re
import sys

names = (
    "ASC_KEY_ID",
    "ASC_ISSUER_ID",
    "ASC_PRIVATE_KEY_PATH",
    "APP_BUNDLE_ID",
    "TESTFLIGHT_GROUP_NAME",
    "SANDBOX_TESTER_EMAIL",
    "TESTFLIGHT_TESTER_EMAILS",
    "AIPEDOMETER_REDACT_APP_ID",
    "AIPEDOMETER_REDACT_GROUP_ID",
    "AIPEDOMETER_REDACT_ROOT_DIR",
)
values = []
for name in names:
    value = os.environ.get(name, "").strip()
    if value:
        values.append(value)
        values.extend(part.strip() for part in value.split(",") if part.strip())

redactions = sorted(set(values), key=len, reverse=True)
email_pattern = re.compile(
    r"(?i)(?<![A-Z0-9._%+-])[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}(?![A-Z0-9._%+-])"
)
for line in sys.stdin:
    for value in redactions:
        line = line.replace(value, "[REDACTED]")
    line = email_pattern.sub("[REDACTED_EMAIL]", line)
    sys.stdout.write(line)
    sys.stdout.flush()
'
}

OUTPUT_ROOT="${ROOT_DIR}/build/ipa"

canonical_output_path() {
  local raw_path="$1"
  local absolute_path
  if [[ "${raw_path}" = /* ]]; then
    absolute_path="${raw_path}"
  else
    absolute_path="${ROOT_DIR}/${raw_path}"
  fi

  case "${absolute_path}" in
    "${OUTPUT_ROOT}"|"${OUTPUT_ROOT}/"*) ;;
    *)
      echo "ERRO: caminho de saida fora de build/ipa." >&2
      exit 1
      ;;
  esac

  local parent
  parent="$(dirname "${absolute_path}")"
  mkdir -p "${parent}"

  local parent_real
  parent_real="$(cd "${parent}" && pwd -P)"
  local resolved
  resolved="${parent_real}/$(basename "${absolute_path}")"

  case "${resolved}" in
    "${OUTPUT_ROOT}"|"${OUTPUT_ROOT}/"*)
      printf '%s\n' "${resolved}"
      ;;
    *)
      echo "ERRO: caminho de saida fora de build/ipa." >&2
      exit 1
      ;;
  esac
}

safe_rm_rf() {
  local target="$1"
  if [[ -z "${target}" || "${target}" == "/" ]]; then
    echo "ERRO: recusando remover caminho invalido." >&2
    exit 1
  fi

  case "${target}" in
    "${OUTPUT_ROOT}/"*)
      rm -rf "${target}" >/dev/null 2>&1 || true
      ;;
    *)
      echo "ERRO: recusando remover caminho fora de build/ipa." >&2
      exit 1
      ;;
  esac
}

APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.mneves.aipedometer}"
GROUP_NAME="${TESTFLIGHT_GROUP_NAME:-IAP Sandbox}"

IPA_DIR="$(canonical_output_path "${IPA_DIR:-build/ipa}")"
ARCHIVE_PATH="$(canonical_output_path "${ARCHIVE_PATH:-${IPA_DIR}/AIPedometer.xcarchive}")"
IPA_PATH="$(canonical_output_path "${IPA_PATH:-${IPA_DIR}/AIPedometer.ipa}")"

if [[ "${AIPEDOMETER_TEST_PAYMENTS_VALIDATE_PATHS_ONLY:-0}" == "1" ]]; then
  echo "Path validation OK"
  exit 0
fi

require_cmd asc
require_cmd xcodebuild
require_cmd python3
require_cmd rg
aipedometer_select_xcode_26

mkdir -p "${IPA_DIR}"

echo "==> 1) Verificando auth do asc (App Store Connect CLI)..."
if ! asc auth status >/dev/null 2>&1; then
  echo "ERRO: falha ao executar 'asc auth status'."
  exit 1
fi

if asc auth status 2>/dev/null | rg -n "No credentials stored" >/dev/null 2>&1; then
  echo "Sem credenciais do App Store Connect no asc."
  echo "Para autenticar sem interacao, defina:"
  echo "- ASC_KEY_ID"
  echo "- ASC_ISSUER_ID"
  echo "- ASC_PRIVATE_KEY_PATH (caminho para AuthKey_XXXX.p8)"
  echo
  echo "E rode:"
  echo "  asc auth login --bypass-keychain --local --skip-validation \\"
  echo "    --name \"AIPedometer\" \\"
  echo "    --key-id \"<ASC_KEY_ID>\" \\"
  echo "    --issuer-id \"<ASC_ISSUER_ID>\" \\"
  echo "    --private-key \"</path/to/AuthKey.p8>\""
  echo
  echo "Obs: este repo ignora .asc/ no git (.gitignore) para evitar vazamento."
  exit 2
fi

echo "==> 2) Descobrindo APP_ID para o bundle configurado..."
if ! APP_JSON="$(asc apps list --bundle-id "${APP_BUNDLE_ID}" --output json 2>/dev/null)"; then
  echo "ERRO: falha ao consultar o app no App Store Connect."
  exit 3
fi
APP_ID="$(
  python3 -c 'import json,sys; data=json.loads(sys.stdin.read() or "[]"); print((data[0].get("id","") if isinstance(data,list) and data else "") or "")' \
    <<<"${APP_JSON}"
)"

if [[ -z "${APP_ID}" ]]; then
  echo "ERRO: nao encontrei o app no App Store Connect para o bundle configurado."
  echo "Dica: confirme se o app existe no ASC e se o bundle id esta correto."
  exit 3
fi

echo "APP_ID obtido."

echo "==> 3) Sandbox Tester (IAP)"
echo "O asc ainda nao oferece 'create' para sandbox testers nesta versao."
echo "O que eu consigo automatizar via CLI:"
echo "- listar: asc sandbox list --email \"EMAIL\""
echo "- limpar historico: asc sandbox clear-history --id \"ID\" --confirm"
echo
if [[ -n "${SANDBOX_TESTER_EMAIL:-}" ]]; then
  echo "Procurando sandbox tester existente pelo email configurado."
  if asc sandbox list --email "${SANDBOX_TESTER_EMAIL}" --output json >/dev/null 2>&1; then
    echo "Consulta concluida sem exibir dados do tester."
  else
    echo "Aviso: nao foi possivel consultar o sandbox tester."
  fi
  echo "Se existir, voce pode limpar historico com:"
  echo "  asc sandbox clear-history --id \"<SANDBOX_TESTER_ID>\" --confirm"
else
  echo "Opcional: defina SANDBOX_TESTER_EMAIL para eu listar/verificar o tester existente."
fi

echo
echo "==> 4) Gerando IPA (Release) para TestFlight..."
echo "Os artefatos serao gravados sob build/ipa."

# ExportOptions (minimal) for App Store / TestFlight distribution.
EXPORT_OPTIONS_PLIST="${IPA_DIR}/ExportOptions-TestFlight.plist"
cat > "${EXPORT_OPTIONS_PLIST}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>uploadBitcode</key>
  <false/>
</dict>
</plist>
PLIST

safe_rm_rf "${ARCHIVE_PATH}"
safe_rm_rf "${IPA_DIR}/export"

xcodebuild \
  -project AIPedometer.xcodeproj \
  -scheme AIPedometer \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "${ARCHIVE_PATH}" \
  archive \
  2>&1 \
  | redact_sensitive_output \
  | tee "${IPA_DIR}/xcodebuild-archive.log"

xcodebuild \
  -archivePath "${ARCHIVE_PATH}" \
  -exportArchive \
  -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
  -exportPath "${IPA_DIR}/export" \
  2>&1 \
  | redact_sensitive_output \
  | tee "${IPA_DIR}/xcodebuild-export.log"

if [[ ! -f "${IPA_DIR}/export/AIPedometer.ipa" ]]; then
  echo "ERRO: IPA nao encontrada apos export."
  exit 4
fi

cp -f "${IPA_DIR}/export/AIPedometer.ipa" "${IPA_PATH}"

echo "==> 5) Garantindo o grupo configurado do TestFlight."
if ! GROUPS_JSON="$(asc testflight beta-groups list --app "${APP_ID}" --output json 2>/dev/null)"; then
  echo "ERRO: falha ao consultar grupos do TestFlight."
  exit 5
fi
GROUP_ID="$(
  GROUPS_JSON="${GROUPS_JSON}" GROUP_NAME="${GROUP_NAME}" python3 - <<'PY'
import json
import os

name = os.environ.get("GROUP_NAME", "").strip()
data = json.loads(os.environ.get("GROUPS_JSON") or "[]")
gid = ""
for g in (data if isinstance(data, list) else []):
    if (g.get("name") or "").strip() == name:
        gid = g.get("id") or ""
        break
print(gid)
PY
)"

if [[ -z "${GROUP_ID}" ]]; then
  echo "Criando grupo..."
  if ! CREATE_JSON="$(asc testflight beta-groups create --app "${APP_ID}" --name "${GROUP_NAME}" --output json 2>/dev/null)"; then
    echo "ERRO: falha ao criar o grupo do TestFlight."
    exit 5
  fi
  GROUP_ID="$(
    python3 -c 'import json,sys; data=json.loads(sys.stdin.read() or "{}"); print((data.get("id","") or ""))' \
      <<<"${CREATE_JSON}"
  )"
fi

if [[ -z "${GROUP_ID}" ]]; then
  echo "ERRO: nao consegui obter/criar group id do TestFlight."
  exit 5
fi

echo "GROUP_ID obtido."

if [[ -n "${TESTFLIGHT_TESTER_EMAILS:-}" ]]; then
  echo "==> 6) Adicionando beta testers ao app/grupo..."
  # Expect comma-separated emails.
  IFS=',' read -r -a emails <<<"${TESTFLIGHT_TESTER_EMAILS}"
  for raw in "${emails[@]}"; do
    email="$(echo "$raw" | xargs)"
    [[ -z "${email}" ]] && continue
    asc testflight beta-testers add --app "${APP_ID}" --email "${email}" --group "${GROUP_ID}" --output json >/dev/null 2>&1
    asc testflight beta-testers invite --app "${APP_ID}" --email "${email}" --group "${GROUP_ID}" --output json >/dev/null 2>&1 || true
    echo "- tester processado."
  done
else
  echo "==> 6) Beta testers"
  echo "Opcional: defina TESTFLIGHT_TESTER_EMAILS=\"email1,email2\" para eu adicionar/invitar automaticamente."
fi

echo
echo "==> 7) Publicando no TestFlight (upload + wait + distribuir)..."
asc publish testflight \
  --app "${APP_ID}" \
  --ipa "${IPA_PATH}" \
  --group "${GROUP_ID}" \
  --wait \
  --output json \
  2>&1 \
  | redact_sensitive_output \
  | tee "${IPA_DIR}/asc-publish-testflight.json"

echo
echo "OK"
echo "- IPA, logs e resumo redigido: build/ipa"
