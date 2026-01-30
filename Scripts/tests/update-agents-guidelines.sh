#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

GUIDELINES_DIR="${TMP_DIR}/guidelines"
mkdir -p "${GUIDELINES_DIR}"

cat > "${GUIDELINES_DIR}/AGENTS.md" <<'EOF'
# AGENTS.md

GUIDELINES-REF is a curated, opinionated knowledge base for building production software with AI agents across security, logging/audit, web/mobile, databases, infra, and language runtimes.

Essentials (apply to every task):
- Always work through lists/todo/plans items; do not stop until all work is done and you are certain it works.
EOF

cat > "${TMP_DIR}/AGENTS.md" <<'EOF'
# Repository Guidelines

## GUIDELINES-REF
Synced from `~/dev/GUIDELINES-REF/AGENTS.md` (use `bash Scripts/check-agents-sync.sh`).
OUTDATED CONTENT
EOF

GUIDELINES_REF_ROOT="${GUIDELINES_DIR}" \
LOCAL_AGENTS="${TMP_DIR}/AGENTS.md" \
bash "${ROOT_DIR}/Scripts/update-agents-guidelines.sh"

GUIDELINES_REF_ROOT="${GUIDELINES_DIR}" \
LOCAL_AGENTS="${TMP_DIR}/AGENTS.md" \
bash "${ROOT_DIR}/Scripts/check-agents-sync.sh"

echo "update-agents-guidelines.sh tests passed."
