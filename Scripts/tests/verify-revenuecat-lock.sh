#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

CHECKER="${ROOT_DIR}/Scripts/verify-revenuecat-lock.sh"
if [[ ! -x "${CHECKER}" ]]; then
  echo "Missing executable RevenueCat lock checker: ${CHECKER}" >&2
  exit 1
fi

readonly DECLARED_REVISION="1111111111111111111111111111111111111111"
readonly RESOLVED_REVISION="2222222222222222222222222222222222222222"

cat >"${TMP_DIR}/project.yml" <<EOF
packages:
  RevenueCat:
    url: https://github.com/RevenueCat/purchases-ios-spm
    revision: ${DECLARED_REVISION}
EOF

cat >"${TMP_DIR}/project.pbxproj" <<EOF
/* Begin XCRemoteSwiftPackageReference section */
    TEST /* XCRemoteSwiftPackageReference "purchases-ios-spm" */ = {
      isa = XCRemoteSwiftPackageReference;
      repositoryURL = "https://github.com/RevenueCat/purchases-ios-spm";
      requirement = {
        kind = revision;
        revision = ${DECLARED_REVISION};
      };
    };
/* End XCRemoteSwiftPackageReference section */
EOF

write_lockfile() {
  local declared_revision="$1"
  local resolved_revision="$2"
  cat >"${TMP_DIR}/Package.resolved" <<EOF
{
  "originHash": "fixture",
  "pins": [
    {
      "identity": "purchases-ios-spm",
      "kind": "remoteSourceControl",
      "location": "https://github.com/RevenueCat/purchases-ios-spm",
      "state": {
        "branch": "${declared_revision}",
        "revision": "${resolved_revision}"
      }
    }
  ],
  "version": 3
}
EOF
}

write_lockfile "${DECLARED_REVISION}" "${RESOLVED_REVISION}"
"${CHECKER}" \
  "${TMP_DIR}/project.yml" \
  "${TMP_DIR}/project.pbxproj" \
  "${TMP_DIR}/Package.resolved" \
  >"${TMP_DIR}/valid.log"
grep -Fqx "RevenueCat dependency lock is coherent." "${TMP_DIR}/valid.log"

write_lockfile "3333333333333333333333333333333333333333" "${RESOLVED_REVISION}"
if "${CHECKER}" \
  "${TMP_DIR}/project.yml" \
  "${TMP_DIR}/project.pbxproj" \
  "${TMP_DIR}/Package.resolved" \
  >"${TMP_DIR}/invalid-branch.log" 2>&1; then
  echo "Expected a lockfile declaration mismatch to fail." >&2
  exit 1
fi
grep -Fq "lockfile branch does not match project.yml" "${TMP_DIR}/invalid-branch.log"

write_lockfile "${DECLARED_REVISION}" "not-a-sha"
if "${CHECKER}" \
  "${TMP_DIR}/project.yml" \
  "${TMP_DIR}/project.pbxproj" \
  "${TMP_DIR}/Package.resolved" \
  >"${TMP_DIR}/invalid-revision.log" 2>&1; then
  echo "Expected an invalid resolved revision to fail." >&2
  exit 1
fi
grep -Fq "lockfile revision is not a full Git SHA" "${TMP_DIR}/invalid-revision.log"

echo "verify-revenuecat-lock.sh tests passed."
