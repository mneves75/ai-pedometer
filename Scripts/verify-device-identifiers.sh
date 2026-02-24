#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ALLOWLIST_PATH_REGEX="${ALLOWLIST_PATH_REGEX:-^Scripts/verify-device-identifiers\\.sh$|^Scripts/verify-device-ids\\.sh$|^Scripts/tests/verify-device-ids\\.sh$|^Scripts/tests/verify-device-identifiers\\.sh$}"

if ! git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERRO: ${ROOT_DIR} nao e um repositorio git valido." >&2
  exit 1
fi

# Apple physical UDID format often appears as 8 hex + '-' + 16 hex.
physical_udid='[A-F0-9]{8}-[A-F0-9]{16}'
# CoreDevice UUID/hash or generic UUID.
uuid='[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}'
# ECID usually appears as long decimal.
ecid='[0-9]{10,}'

patterns=(
  "platform=(iOS|watchOS|tvOS|visionOS),id=(${physical_udid}|${uuid})"
  "--device[[:space:]]+(${physical_udid}|${uuid}|${ecid})"
  "(ECID|DEVICE_ID|DEVICE_UUID|DEVICE_UDID)[^[:alnum:]]+(${physical_udid}|${uuid}|${ecid})"
  "MyDevice[^[:alnum:]]+(${physical_udid}|${uuid}|${ecid})"
)

fail=0

for pattern in "${patterns[@]}"; do
  matches="$(git -C "${ROOT_DIR}" grep -n -I -E -- "${pattern}" || true)"

  if [[ -n "${matches}" ]]; then
    matches="$(
      awk -F: -v re="${ALLOWLIST_PATH_REGEX}" '
        $1 !~ re { print }
      ' <<<"${matches}"
    )"
  fi

  if [[ -n "${matches}" ]]; then
    fail=1
    echo "ERRO: padrao proibido encontrado (${pattern}):" >&2
    echo "${matches}" >&2
    echo >&2
  fi
done

if [[ "${fail}" -ne 0 ]]; then
  echo "Falhou: existem identificadores sensiveis de devices hardcoded em arquivos versionados." >&2
  exit 1
fi

echo "OK: nenhum identificador sensivel de device hardcoded encontrado."
