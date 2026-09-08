#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/docs"
printf '%s\n' '# Local verification' > "${TMP_DIR}/docs/testing.md"
printf '%s\n' '# AGENTS.md' '' '## Verification' '' '[Tests](docs/testing.md)' > "${TMP_DIR}/AGENTS.md"
printf '%s\n' '@AGENTS.md' > "${TMP_DIR}/CLAUDE.md"

check_contract() {
  GUIDELINES_REF_ROOT="${TMP_DIR}/no-external-checkout" \
    LOCAL_AGENTS="${TMP_DIR}/AGENTS.md" \
    bash "${ROOT_DIR}/Scripts/check-agents-sync.sh" "${TMP_DIR}"
}

expect_failure() {
  if check_contract; then
    echo "Expected invalid instruction contract to fail: $1" >&2
    exit 1
  fi
}

check_contract
printf '%s\n' 'Duplicated rules' >> "${TMP_DIR}/CLAUDE.md"
expect_failure 'Claude duplicates rules'
printf '%s\n' '@AGENTS.md' > "${TMP_DIR}/CLAUDE.md"

mv "${TMP_DIR}/docs/testing.md" "${TMP_DIR}/docs/moved.md"
expect_failure 'missing linked document'
mv "${TMP_DIR}/docs/moved.md" "${TMP_DIR}/docs/testing.md"

printf '\n## Verification\n' >> "${TMP_DIR}/AGENTS.md"
expect_failure 'duplicate section'
printf '%s\n' '# AGENTS.md' '' '## Verification' '' '[Tests](docs/testing.md)' > "${TMP_DIR}/AGENTS.md"

python3 -c 'import sys; print("x" * 16001)' >> "${TMP_DIR}/AGENTS.md"
expect_failure 'oversized always-loaded contract'
printf '%s\n' '# AGENTS.md' > "${TMP_DIR}/AGENTS.md"
expect_failure 'empty contract'
rm "${TMP_DIR}/AGENTS.md"
expect_failure 'missing contract'

echo 'Agent instruction contract tests passed.'
