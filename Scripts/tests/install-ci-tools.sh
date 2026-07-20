#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

INSTALLER="${ROOT_DIR}/Scripts/install-ci-tools.sh"
if [[ ! -f "${INSTALLER}" ]]; then
  echo "Missing CI tool installer: ${INSTALLER}" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${INSTALLER}"

assert_asset() {
  local tool="$1"
  local arch="$2"
  local expected="$3"
  local actual
  actual="$(aipedometer_ci_tool_asset "${tool}" "${arch}")"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "Unexpected asset for ${tool}/${arch}." >&2
    echo "expected: ${expected}" >&2
    echo "actual:   ${actual}" >&2
    exit 1
  fi
}

assert_asset \
  xcodegen \
  arm64 \
  "https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip|4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806|zip|xcodegen/bin/xcodegen"
assert_asset \
  ast-grep \
  arm64 \
  "https://github.com/ast-grep/ast-grep/releases/download/0.44.1/app-aarch64-apple-darwin.zip|0a2fef273b0ff1238b8307add911714f92021d25b919fa3ec9b6b2e046bb29cf|zip|ast-grep"
assert_asset \
  ast-grep \
  x86_64 \
  "https://github.com/ast-grep/ast-grep/releases/download/0.44.1/app-x86_64-apple-darwin.zip|46584f3e4f67e9ae482de69e71e4e4aa88e68da322316fdd25ad73f2621ddbc5|zip|ast-grep"
assert_asset \
  ripgrep \
  arm64 \
  "https://github.com/BurntSushi/ripgrep/releases/download/15.2.0/ripgrep-15.2.0-aarch64-apple-darwin.tar.gz|3750b2e93f37e0c692657da574d7019a101c0084da05a790c83fd335bad973e4|tar.gz|ripgrep-15.2.0-aarch64-apple-darwin/rg"
assert_asset \
  ripgrep \
  x86_64 \
  "https://github.com/BurntSushi/ripgrep/releases/download/15.2.0/ripgrep-15.2.0-x86_64-apple-darwin.tar.gz|af7825fcc69a2afc7a7aea55fc9af90e26421d8f20fe59df32e233c0b8a231c1|tar.gz|ripgrep-15.2.0-x86_64-apple-darwin/rg"
assert_asset \
  actionlint \
  arm64 \
  "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_darwin_arm64.tar.gz|aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f|tar.gz|actionlint"
assert_asset \
  actionlint \
  x86_64 \
  "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_darwin_amd64.tar.gz|5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644|tar.gz|actionlint"
assert_asset \
  shellcheck \
  arm64 \
  "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.darwin.aarch64.tar.gz|339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f|tar.gz|shellcheck-v0.11.0/shellcheck"
assert_asset \
  shellcheck \
  x86_64 \
  "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.darwin.x86_64.tar.gz|c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51|tar.gz|shellcheck-v0.11.0/shellcheck"

UNSUPPORTED_LOG="${TMP_DIR}/unsupported.log"
if aipedometer_ci_tool_asset ast-grep powerpc >"${UNSUPPORTED_LOG}" 2>&1; then
  echo "Expected unsupported CI architecture to fail closed." >&2
  exit 1
fi
grep -Fqx "ERRO: arquitetura macOS nao suportada: powerpc" "${UNSUPPORTED_LOG}"

PAYLOAD="${TMP_DIR}/payload"
printf '%s' 'verified payload' >"${PAYLOAD}"
PAYLOAD_SHA="$(shasum -a 256 "${PAYLOAD}" | awk '{print $1}')"
aipedometer_verify_sha256 "${PAYLOAD}" "${PAYLOAD_SHA}"
if aipedometer_verify_sha256 "${PAYLOAD}" "0000000000000000000000000000000000000000000000000000000000000000" >/dev/null 2>&1; then
  echo "Expected checksum mismatch to fail closed." >&2
  exit 1
fi

FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${FAKE_BIN}"
cat >"${FAKE_BIN}/xcodegen" <<'EOF'
#!/usr/bin/env bash
echo "Version: 2.46.0"
EOF
cat >"${FAKE_BIN}/ast-grep" <<'EOF'
#!/usr/bin/env bash
echo "ast-grep 0.44.1"
EOF
cat >"${FAKE_BIN}/rg" <<'EOF'
#!/usr/bin/env bash
echo "ripgrep 15.2.0"
EOF
cat >"${FAKE_BIN}/actionlint" <<'EOF'
#!/usr/bin/env bash
echo "1.7.12"
EOF
cat >"${FAKE_BIN}/shellcheck" <<'EOF'
#!/usr/bin/env bash
printf 'ShellCheck - shell script analysis tool\nversion: 0.11.0\n'
EOF
chmod +x "${FAKE_BIN}/xcodegen" "${FAKE_BIN}/ast-grep" "${FAKE_BIN}/rg" \
  "${FAKE_BIN}/actionlint" "${FAKE_BIN}/shellcheck"

aipedometer_assert_tool_version xcodegen "${FAKE_BIN}/xcodegen"
aipedometer_assert_tool_version ast-grep "${FAKE_BIN}/ast-grep"
aipedometer_assert_tool_version ripgrep "${FAKE_BIN}/rg"
aipedometer_assert_tool_version actionlint "${FAKE_BIN}/actionlint"
aipedometer_assert_tool_version shellcheck "${FAKE_BIN}/shellcheck"

cat >"${FAKE_BIN}/ast-grep" <<'EOF'
#!/usr/bin/env bash
echo "ast-grep 0.44.0"
EOF
chmod +x "${FAKE_BIN}/ast-grep"
if aipedometer_assert_tool_version ast-grep "${FAKE_BIN}/ast-grep" >/dev/null 2>&1; then
  echo "Expected version mismatch to fail closed." >&2
  exit 1
fi

echo "install-ci-tools.sh tests passed."
