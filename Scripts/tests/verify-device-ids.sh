#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

TEST_REPO="${TMP_DIR}/repo"
mkdir -p "${TEST_REPO}"

git -C "${TEST_REPO}" init >/dev/null
git -C "${TEST_REPO}" config user.name "Test User"
git -C "${TEST_REPO}" config user.email "test@example.com"

physical_udid_a="00008101"
physical_udid_b="000000000000001E"
physical_udid="${physical_udid_a}-${physical_udid_b}"

uuid_a="AAAABBBB"
uuid_b="CCCC"
uuid_c="DDDD"
uuid_d="EEEE"
uuid_e="FFFFFFFFFFFF"
coredevice_uuid="${uuid_a}-${uuid_b}-${uuid_c}-${uuid_d}-${uuid_e}"

ecid="123456789012345"

cat > "${TEST_REPO}/commands.md" <<EOF
xcodebuild -scheme AIPedometer -destination "platform=iOS,id=${physical_udid}" build
xcrun devicectl device install app --device ${coredevice_uuid} /tmp/AIPedometer.app
ECID: ${ecid}
EOF

git -C "${TEST_REPO}" add commands.md
git -C "${TEST_REPO}" commit -m "Add hardcoded command" >/dev/null

if ROOT_DIR="${TEST_REPO}" bash "${PROJECT_ROOT}/Scripts/verify-device-identifiers.sh"; then
  echo "Expected verify-device-identifiers.sh to fail with hardcoded identifiers." >&2
  exit 1
fi

cat > "${TEST_REPO}/commands.md" <<'EOF'
xcodebuild -scheme AIPedometer -destination 'platform=iOS,name=MyDevice' build
xcrun devicectl device install app --device MyDevice /tmp/AIPedometer.app
EOF

git -C "${TEST_REPO}" add commands.md
git -C "${TEST_REPO}" commit -m "Remove hardcoded IDs" >/dev/null

ROOT_DIR="${TEST_REPO}" bash "${PROJECT_ROOT}/Scripts/verify-device-identifiers.sh"

# A large allowlisted match set must be drained by the filter instead of being
# replayed through a here-string, which can fill Bash's heredoc pipe.
: > "${TEST_REPO}/allowlisted.txt"
for _ in {1..3000}; do
  printf 'ECID: %s\n' "${ecid}" >> "${TEST_REPO}/allowlisted.txt"
done
git -C "${TEST_REPO}" add allowlisted.txt
git -C "${TEST_REPO}" commit -m "Add large allowlisted fixture" >/dev/null

ROOT_DIR="${TEST_REPO}" \
ALLOWLIST_PATH_REGEX='^allowlisted\.txt$' \
bash "${PROJECT_ROOT}/Scripts/verify-device-identifiers.sh"

MOCK_BIN="${TMP_DIR}/bin"
mkdir -p "${MOCK_BIN}"
export AIPEDOMETER_TEST_REAL_GIT
AIPEDOMETER_TEST_REAL_GIT="$(command -v git)"
cat > "${MOCK_BIN}/git" <<'EOF'
#!/usr/bin/env bash
if [[ "${3:-}" == grep ]]; then
  echo 'synthetic Git scan failure' >&2
  exit 2
fi
exec "${AIPEDOMETER_TEST_REAL_GIT}" "$@"
EOF
chmod +x "${MOCK_BIN}/git"
if PATH="${MOCK_BIN}:${PATH}" ROOT_DIR="${TEST_REPO}" \
  bash "${PROJECT_ROOT}/Scripts/verify-device-identifiers.sh" > "${TMP_DIR}/scan-error.txt" 2>&1; then
  echo 'Expected Git scan errors to fail closed.' >&2
  exit 1
fi
grep -Fq 'synthetic Git scan failure' "${TMP_DIR}/scan-error.txt"

echo "verify-device-identifiers.sh tests passed."
