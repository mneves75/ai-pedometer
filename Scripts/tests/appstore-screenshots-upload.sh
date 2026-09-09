#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SCREENSHOTS_ROOT="${TMP_DIR}/screenshots"
MOCK_BIN="${TMP_DIR}/bin"
mkdir -p "${SCREENSHOTS_ROOT}/iphone_65" "${SCREENSHOTS_ROOT}/ipad_13" "${MOCK_BIN}"
: > "${SCREENSHOTS_ROOT}/iphone_65/01.png"
: > "${SCREENSHOTS_ROOT}/ipad_13/01.png"

cat > "${MOCK_BIN}/sips" <<'EOF'
#!/usr/bin/env bash
if [[ "${MOCK_INVALID_SCREENSHOT:-0}" == "1" && "$*" == *iphone_65* ]]; then
  printf '  pixelWidth: 1\n  pixelHeight: 1\n'
elif [[ "$*" == *iphone_65* ]]; then
  printf '  pixelWidth: 1284\n  pixelHeight: 2778\n'
else
  printf '  pixelWidth: 2064\n  pixelHeight: 2752\n'
fi
EOF
chmod +x "${MOCK_BIN}/sips"

if MOCK_INVALID_SCREENSHOT=1 PATH="${MOCK_BIN}:${PATH}" \
  bash "${ROOT_DIR}/Scripts/appstore-screenshots-upload.sh" \
  --screenshots-root "${SCREENSHOTS_ROOT}" \
  --version-localization-id synthetic-localization \
  --dry-run > "${TMP_DIR}/invalid.log" 2>&1; then
  echo "Expected direct upload to reject invalid screenshot dimensions." >&2
  exit 1
fi

if ! grep -Fq 'dimensão inválida' "${TMP_DIR}/invalid.log"; then
  echo "Expected screenshot validation to explain the invalid dimensions." >&2
  exit 1
fi

PATH="${MOCK_BIN}:${PATH}" bash "${ROOT_DIR}/Scripts/appstore-screenshots-upload.sh" \
  --screenshots-root "${SCREENSHOTS_ROOT}" \
  --version-localization-id synthetic-localization \
  --dry-run > "${TMP_DIR}/valid.log"

if [[ "$(grep -c '^\[dry-run\] asc screenshots upload ' "${TMP_DIR}/valid.log")" -ne 2 ]]; then
  echo "Expected a valid package to reach both dry-run uploads." >&2
  exit 1
fi

echo "appstore-screenshots-upload.sh tests passed."
