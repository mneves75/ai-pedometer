#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

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
  AGENTS.md CLAUDE.md Scripts/check-agents-sync.sh Scripts/verify-device-identifiers.sh \
  docs/agents/issue-tracker.md \
  sgconfig.yml \
  rules/ast-grep/swift-no-force-cast.yml \
  rules/ast-grep/swift-no-force-try.yml

AST_GREP_BIN="${PASS_AST_GREP}" \
GIT_INDEX_FILE="${TEST_INDEX}" \
bash "${ROOT_DIR}/.githooks/pre-commit"

if AST_GREP_BIN="${FAIL_AST_GREP}" \
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

if AST_GREP_BIN="${STAGED_SNAPSHOT_AST_GREP}" \
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

if AST_GREP_BIN="ast-grep" \
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

# This synthetic identifier exists only in the index, never in the working tree.
SYNTHETIC_DEVICE_LABEL='Device ID'
STAGED_DEVICE_BLOB="$(printf '%s: %s\n' "${SYNTHETIC_DEVICE_LABEL}" '12345678-1234-1234-1234-123456789ABC' | git -C "${ROOT_DIR}" hash-object -w --stdin)"
GIT_INDEX_FILE="${TEST_INDEX}" git -C "${ROOT_DIR}" update-index \
  --add --cacheinfo "100644,${STAGED_DEVICE_BLOB},StagedDevice.txt"
if AST_GREP_BIN="${PASS_AST_GREP}" \
  GIT_INDEX_FILE="${TEST_INDEX}" \
  bash "${ROOT_DIR}/.githooks/pre-commit" > "${TMP_DIR}/device-scan.txt" 2>&1; then
  echo "Expected pre-commit to reject a device identifier present only in the index." >&2
  exit 1
fi
grep -Fq 'StagedDevice.txt' "${TMP_DIR}/device-scan.txt"
if grep -Fq '12345678-1234-1234-1234-123456789ABC' "${TMP_DIR}/device-scan.txt"; then
  echo 'Device verification must not print the prohibited identifier.' >&2
  exit 1
fi
GIT_INDEX_FILE="${TEST_INDEX}" git -C "${ROOT_DIR}" update-index --force-remove StagedDevice.txt

# The working tree remains valid; only the staged Claude import is invalid.
INVALID_IMPORT_BLOB="$(printf '%s\n' '@missing.md' | git -C "${ROOT_DIR}" hash-object -w --stdin)"
GIT_INDEX_FILE="${TEST_INDEX}" git -C "${ROOT_DIR}" update-index \
  --add --cacheinfo "100644,${INVALID_IMPORT_BLOB},CLAUDE.md"

if AST_GREP_BIN="${PASS_AST_GREP}" \
  GIT_INDEX_FILE="${TEST_INDEX}" \
  bash "${ROOT_DIR}/.githooks/pre-commit"; then
  echo "Expected pre-commit to fail but it passed." >&2
  exit 1
fi

echo "pre-commit hook tests passed."
