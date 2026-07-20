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

PASS_AST_GREP="${TMP_DIR}/ast-grep-pass"
FAIL_AST_GREP="${TMP_DIR}/ast-grep-fail"
STAGED_SNAPSHOT_AST_GREP="${TMP_DIR}/ast-grep-staged-snapshot"
TEST_INDEX="${TMP_DIR}/git-index"
TEST_OBJECTS="${TMP_DIR}/git-objects"
STAGED_SNAPSHOT_MARKER="${TMP_DIR}/staged-snapshot-seen"

mkdir -p "${TEST_OBJECTS}"
REPOSITORY_OBJECTS="$(
  env -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
    git -C "${ROOT_DIR}" rev-parse --path-format=absolute --git-path objects
)"
export GIT_OBJECT_DIRECTORY="${TEST_OBJECTS}"
export GIT_ALTERNATE_OBJECT_DIRECTORIES="${REPOSITORY_OBJECTS}"

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${PASS_AST_GREP}"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "${FAIL_AST_GREP}"
cat > "${STAGED_SNAPSHOT_AST_GREP}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -f "StagedOnly.swift" ]] && grep -Fq 'try!' "StagedOnly.swift"; then
  : > "${STAGED_SNAPSHOT_MARKER}"
  exit 1
fi

exit 0
EOF
chmod +x "${PASS_AST_GREP}" "${FAIL_AST_GREP}" "${STAGED_SNAPSHOT_AST_GREP}"

GIT_INDEX_FILE="${TEST_INDEX}" git -C "${ROOT_DIR}" read-tree HEAD
GIT_INDEX_FILE="${TEST_INDEX}" git -C "${ROOT_DIR}" add -- \
  sgconfig.yml \
  rules/ast-grep/swift-no-force-cast.yml \
  rules/ast-grep/swift-no-force-try.yml

printf '%s\n' \
  '# AGENTS.md' \
  '' \
  'GUIDELINES-REF is a curated, opinionated knowledge base for building production software with AI agents across security, logging/audit, web/mobile, databases, infra, and language runtimes.' \
  '' \
  'Essentials (apply to every task):' \
  '- Always work through lists/todo/plans items; do not stop until all work is done and you are certain it works.' \
  > "${GUIDELINES_DIR}/AGENTS.md"

# shellcheck disable=SC2016 # The fixture intentionally contains literal backticks.
printf '%s\n' \
  '# Repository Guidelines' \
  '' \
  '## GUIDELINES-REF' \
  'Synced from `~/dev/GUIDELINES-REF/AGENTS.md` (use `bash Scripts/update-agents-guidelines.sh` then `bash Scripts/check-agents-sync.sh`).' \
  'GUIDELINES-REF is a curated, opinionated knowledge base for building production software with AI agents across security, logging/audit, web/mobile, databases, infra, and language runtimes.' \
  '' \
  'Essentials (apply to every task):' \
  '- Always work through lists/todo/plans items; do not stop until all work is done and you are certain it works.' \
  > "${TMP_DIR}/AGENTS.md"

GUIDELINES_REF_ROOT="${GUIDELINES_DIR}" \
LOCAL_AGENTS="${TMP_DIR}/AGENTS.md" \
AST_GREP_BIN="${PASS_AST_GREP}" \
GIT_INDEX_FILE="${TEST_INDEX}" \
bash "${ROOT_DIR}/.githooks/pre-commit"

if GUIDELINES_REF_ROOT="${GUIDELINES_DIR}" \
  LOCAL_AGENTS="${TMP_DIR}/AGENTS.md" \
  AST_GREP_BIN="${FAIL_AST_GREP}" \
  GIT_INDEX_FILE="${TEST_INDEX}" \
  bash "${ROOT_DIR}/.githooks/pre-commit"; then
  echo "Expected pre-commit to fail when ast-grep reports a finding." >&2
  exit 1
fi

STAGED_VIOLATION_BLOB="$(printf '%s\n' 'let value = try! riskyOperation()' | git -C "${ROOT_DIR}" hash-object -w --stdin)"
GIT_INDEX_FILE="${TEST_INDEX}" git -C "${ROOT_DIR}" update-index \
  --add --cacheinfo "100644,${STAGED_VIOLATION_BLOB},StagedOnly.swift"
GIT_INDEX_FILE="${TEST_INDEX}" git -C "${ROOT_DIR}" update-index \
  --skip-worktree StagedOnly.swift

if GUIDELINES_REF_ROOT="${GUIDELINES_DIR}" \
  LOCAL_AGENTS="${TMP_DIR}/AGENTS.md" \
  AST_GREP_BIN="${STAGED_SNAPSHOT_AST_GREP}" \
  STAGED_SNAPSHOT_MARKER="${STAGED_SNAPSHOT_MARKER}" \
  GIT_INDEX_FILE="${TEST_INDEX}" \
  bash "${ROOT_DIR}/.githooks/pre-commit"; then
  echo "Expected pre-commit to fail for a violation present only in the staged snapshot." >&2
  exit 1
fi

if [[ ! -f "${STAGED_SNAPSHOT_MARKER}" ]]; then
  echo "Expected ast-grep to inspect the staged snapshot." >&2
  exit 1
fi

GIT_INDEX_FILE="${TEST_INDEX}" git -C "${ROOT_DIR}" update-index \
  --no-skip-worktree StagedOnly.swift
GIT_INDEX_FILE="${TEST_INDEX}" git -C "${ROOT_DIR}" update-index --force-remove StagedOnly.swift

IGNORED_STAGED_BLOB="$(printf '%s\n' 'let value = try! ignoredRiskyOperation()' | git -C "${ROOT_DIR}" hash-object -w --stdin)"
IGNORE_RULE_BLOB="$(printf '%s\n' 'IgnoredStaged.swift' | git -C "${ROOT_DIR}" hash-object -w --stdin)"
IGNORED_SCAN_OUTPUT="${TMP_DIR}/ignored-staged-scan.txt"

GIT_INDEX_FILE="${TEST_INDEX}" git -C "${ROOT_DIR}" update-index \
  --add --cacheinfo "100644,${IGNORED_STAGED_BLOB},IgnoredStaged.swift"
GIT_INDEX_FILE="${TEST_INDEX}" git -C "${ROOT_DIR}" update-index \
  --add --cacheinfo "100644,${IGNORE_RULE_BLOB},.gitignore"

if GUIDELINES_REF_ROOT="${GUIDELINES_DIR}" \
  LOCAL_AGENTS="${TMP_DIR}/AGENTS.md" \
  AST_GREP_BIN="ast-grep" \
  GIT_INDEX_FILE="${TEST_INDEX}" \
  bash "${ROOT_DIR}/.githooks/pre-commit" > "${IGNORED_SCAN_OUTPUT}" 2>&1; then
  echo "Expected pre-commit to reject an ignored path present in the staged snapshot." >&2
  exit 1
fi

if ! grep -Fq 'swift-no-force-try' "${IGNORED_SCAN_OUTPUT}"; then
  echo "Expected swift-no-force-try to report the ignored staged violation." >&2
  cat "${IGNORED_SCAN_OUTPUT}" >&2
  exit 1
fi

GIT_INDEX_FILE="${TEST_INDEX}" git -C "${ROOT_DIR}" update-index --force-remove IgnoredStaged.swift
GIT_INDEX_FILE="${TEST_INDEX}" git -C "${ROOT_DIR}" add .gitignore

printf "\nEXTRA\n" >> "${TMP_DIR}/AGENTS.md"

if GUIDELINES_REF_ROOT="${GUIDELINES_DIR}" \
  LOCAL_AGENTS="${TMP_DIR}/AGENTS.md" \
  AST_GREP_BIN="${PASS_AST_GREP}" \
  GIT_INDEX_FILE="${TEST_INDEX}" \
  bash "${ROOT_DIR}/.githooks/pre-commit"; then
  echo "Expected pre-commit to fail but it passed." >&2
  exit 1
fi

echo "pre-commit hook tests passed."
