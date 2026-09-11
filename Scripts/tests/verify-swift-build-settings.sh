#!/usr/bin/env bash
set -euo pipefail

# Regression tests for Scripts/verify-swift-build-settings.sh.
#
# The gate exists because 16 invented SWIFT_UPCOMING_FEATURE_* names lived in project.yml for
# months — Xcode ignores an unknown setting silently. A gate for that class is only worth having
# if it actually fires, so a planted violation is the central case here, not an afterthought.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT_DIR}/Scripts/verify-swift-build-settings.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() { echo "$1" >&2; exit 1; }

# The real project.yml must pass. If this breaks, either a bad setting landed or the gate rotted.
if ! bash "${SCRIPT}" "${ROOT_DIR}/project.yml" >/dev/null 2>&1; then
  bash "${SCRIPT}" "${ROOT_DIR}/project.yml" >&2 || true
  fail "Expected the repository's own project.yml to pass."
fi

# NEGATIVE CONTROL: a name Xcode does not define must fail, and must be named in the output.
PLANTED="${TMP_DIR}/planted.yml"
cat >"${PLANTED}" <<'EOF'
name: Fixture
settings:
  base:
    SWIFT_VERSION: 6.2
    SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY: YES
    SWIFT_UPCOMING_FEATURE_SWIFT_6: YES
EOF
LOG="${TMP_DIR}/planted.log"
if bash "${SCRIPT}" "${PLANTED}" >"${LOG}" 2>&1; then
  fail "Expected a fabricated SWIFT_* setting to fail the gate."
fi
grep -q 'SWIFT_UPCOMING_FEATURE_SWIFT_6' "${LOG}" \
  || { cat "${LOG}" >&2; fail "Expected the offending setting to be named in the failure."; }

# CLEAN CONTROL: a real setting this project does not use must NOT be reported.
CLEAN="${TMP_DIR}/clean.yml"
cat >"${CLEAN}" <<'EOF'
name: Fixture
settings:
  base:
    SWIFT_VERSION: 6.2
    SWIFT_UPCOMING_FEATURE_INFER_SENDABLE_FROM_CAPTURES: YES
    SWIFT_UPCOMING_FEATURE_REGION_BASED_ISOLATION: YES
EOF
bash "${SCRIPT}" "${CLEAN}" >/dev/null 2>&1 \
  || fail "Expected real Xcode-defined settings to pass even when unused by this project."

# A setting named only inside a comment must not be treated as declared.
COMMENTED="${TMP_DIR}/commented.yml"
cat >"${COMMENTED}" <<'EOF'
name: Fixture
settings:
  base:
    # Do not re-add SWIFT_UPCOMING_FEATURE_STRICT_DOUBLE: it does not exist.
    SWIFT_VERSION: 6.2
EOF
bash "${SCRIPT}" "${COMMENTED}" >/dev/null 2>&1 \
  || fail "Expected a setting mentioned only in a comment to be ignored."

# A missing project file must fail rather than pass vacuously.
if bash "${SCRIPT}" "${TMP_DIR}/does-not-exist.yml" >/dev/null 2>&1; then
  fail "Expected a missing project file to fail, not pass empty."
fi

# The gate must run under /bin/bash. macOS ships bash 3.2 there and GitHub's macOS runners use it,
# so a bash 4 builtin (mapfile, readarray, declare -A, ${x^^}) passes on a dev machine with a
# homebrew bash and dies in CI — which is exactly how this script first shipped broken.
if [[ -x /bin/bash ]]; then
  /bin/bash "${SCRIPT}" "${ROOT_DIR}/project.yml" >/dev/null 2>&1 \
    || fail "Expected the gate to run under /bin/bash ($(/bin/bash --version | head -1)); avoid bash 4+ builtins."
  BAD_LOG="${TMP_DIR}/bash32.log"
  if /bin/bash "${SCRIPT}" "${PLANTED}" >"${BAD_LOG}" 2>&1; then
    fail "Expected the planted setting to fail under /bin/bash too."
  fi
  grep -q 'SWIFT_UPCOMING_FEATURE_SWIFT_6' "${BAD_LOG}" \
    || { cat "${BAD_LOG}" >&2; fail "Expected the same diagnosis under /bin/bash."; }
fi

echo "verify-swift-build-settings.sh tests passed."
