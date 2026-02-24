#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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

require_cmd asc
require_cmd xcodebuild
require_cmd python3
require_cmd rg

APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.mneves.aipedometer}"
GROUP_NAME="${TESTFLIGHT_GROUP_NAME:-IAP Sandbox}"

IPA_DIR="${IPA_DIR:-build/ipa}"
ARCHIVE_PATH="${ARCHIVE_PATH:-${IPA_DIR}/AIPedometer.xcarchive}"
IPA_PATH="${IPA_PATH:-${IPA_DIR}/AIPedometer.ipa}"

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
  echo "    --key-id \"${ASC_KEY_ID:-<ASC_KEY_ID>}\" \\"
  echo "    --issuer-id \"${ASC_ISSUER_ID:-<ASC_ISSUER_ID>}\" \\"
  echo "    --private-key \"${ASC_PRIVATE_KEY_PATH:-</path/to/AuthKey.p8>}\""
  echo
  echo "Obs: este repo ignora .asc/ no git (.gitignore) para evitar vazamento."
  exit 2
fi

echo "==> 2) Descobrindo APP_ID para bundle id ${APP_BUNDLE_ID}..."
APP_JSON="$(asc apps list --bundle-id "${APP_BUNDLE_ID}" --output json)"
APP_ID="$(
  python3 -c 'import json,sys; data=json.loads(sys.stdin.read() or "[]"); print((data[0].get("id","") if isinstance(data,list) and data else "") or "")' \
    <<<"${APP_JSON}"
)"

if [[ -z "${APP_ID}" ]]; then
  echo "ERRO: nao encontrei o app no App Store Connect para bundle id: ${APP_BUNDLE_ID}"
  echo "Dica: confirme se o app existe no ASC e se o bundle id esta correto."
  exit 3
fi

echo "APP_ID=${APP_ID}"

echo "==> 3) Sandbox Tester (IAP)"
echo "O asc ainda nao oferece 'create' para sandbox testers nesta versao."
echo "O que eu consigo automatizar via CLI:"
echo "- listar: asc sandbox list --email \"EMAIL\""
echo "- limpar historico: asc sandbox clear-history --id \"ID\" --confirm"
echo
if [[ -n "${SANDBOX_TESTER_EMAIL:-}" ]]; then
  echo "Procurando sandbox tester existente por email: ${SANDBOX_TESTER_EMAIL}"
  asc sandbox list --email "${SANDBOX_TESTER_EMAIL}" --output table || true
  echo "Se existir, voce pode limpar historico com:"
  echo "  asc sandbox clear-history --id \"<SANDBOX_TESTER_ID>\" --confirm"
else
  echo "Opcional: defina SANDBOX_TESTER_EMAIL para eu listar/verificar o tester existente."
fi

echo
echo "==> 4) Gerando IPA (Release) para TestFlight..."
echo "Archive: ${ARCHIVE_PATH}"
echo "IPA:     ${IPA_PATH}"

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

rm -rf "${ARCHIVE_PATH}" "${IPA_DIR}/export" >/dev/null 2>&1 || true

xcodebuild \
  -project AIPedometer.xcodeproj \
  -scheme AIPedometer \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "${ARCHIVE_PATH}" \
  archive \
  | tee "${IPA_DIR}/xcodebuild-archive.log"

xcodebuild \
  -archivePath "${ARCHIVE_PATH}" \
  -exportArchive \
  -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
  -exportPath "${IPA_DIR}/export" \
  | tee "${IPA_DIR}/xcodebuild-export.log"

if [[ ! -f "${IPA_DIR}/export/AIPedometer.ipa" ]]; then
  echo "ERRO: IPA nao encontrada apos export. Esperado: ${IPA_DIR}/export/AIPedometer.ipa"
  exit 4
fi

cp -f "${IPA_DIR}/export/AIPedometer.ipa" "${IPA_PATH}"

echo "==> 5) Garantindo grupo do TestFlight: ${GROUP_NAME}"
GROUPS_JSON="$(asc testflight beta-groups list --app "${APP_ID}" --output json)"
GROUP_ID="$(
  GROUP_NAME="${GROUP_NAME}" python3 -c 'import json,os,sys; name=os.environ.get("GROUP_NAME","").strip(); data=json.loads(sys.stdin.read() or "[]"); gid="";\n\nfor g in (data if isinstance(data,list) else []):\n  if (g.get("name") or "").strip()==name:\n    gid=g.get("id") or \"\"; break\nprint(gid)' \
    <<<"${GROUPS_JSON}"
)"

if [[ -z "${GROUP_ID}" ]]; then
  echo "Criando grupo..."
  CREATE_JSON="$(asc testflight beta-groups create --app "${APP_ID}" --name "${GROUP_NAME}" --output json)"
  GROUP_ID="$(
    python3 -c 'import json,sys; data=json.loads(sys.stdin.read() or "{}"); print((data.get("id","") or ""))' \
      <<<"${CREATE_JSON}"
  )"
fi

if [[ -z "${GROUP_ID}" ]]; then
  echo "ERRO: nao consegui obter/criar group id do TestFlight."
  exit 5
fi

echo "GROUP_ID=${GROUP_ID}"

if [[ -n "${TESTFLIGHT_TESTER_EMAILS:-}" ]]; then
  echo "==> 6) Adicionando beta testers ao app/grupo..."
  # Expect comma-separated emails.
  IFS=',' read -r -a emails <<<"${TESTFLIGHT_TESTER_EMAILS}"
  for raw in "${emails[@]}"; do
    email="$(echo "$raw" | xargs)"
    [[ -z "${email}" ]] && continue
    asc testflight beta-testers add --app "${APP_ID}" --email "${email}" --group "${GROUP_ID}" --output json >/dev/null
    asc testflight beta-testers invite --app "${APP_ID}" --email "${email}" --group "${GROUP_ID}" --output json >/dev/null || true
    echo "- ${email}"
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
  | tee "${IPA_DIR}/asc-publish-testflight.json"

echo
echo "OK"
echo "- IPA: ${IPA_PATH}"
echo "- Logs: ${IPA_DIR}/*.log"
echo "- Publish: ${IPA_DIR}/asc-publish-testflight.json"
