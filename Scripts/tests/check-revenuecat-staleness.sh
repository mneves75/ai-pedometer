#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

CHECKER="${ROOT_DIR}/Scripts/check-revenuecat-staleness.sh"
if [[ ! -f "${CHECKER}" ]]; then
  echo "Missing RevenueCat staleness checker: ${CHECKER}" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${CHECKER}"

PROJECT_FILE="${TMP_DIR}/project.yml"
cat >"${PROJECT_FILE}" <<'EOF'
packages:
  RevenueCat:
    url: https://github.com/RevenueCat/purchases-ios-spm
    revision: 72ab166846656b33a8d1a80c541cf7359e467f4d
EOF

CURRENT_TAG="${TMP_DIR}/current-tag.json"
LATEST_RELEASE="${TMP_DIR}/latest-release.json"
LATEST_REF="${TMP_DIR}/latest-ref.json"
LATEST_TAG="${TMP_DIR}/latest-tag.json"

cat >"${CURRENT_TAG}" <<'EOF'
{"tag":"5.78.0","object":{"sha":"629a56ecef190469914b8f0914bf0446363eb09f","type":"commit"}}
EOF
cat >"${LATEST_RELEASE}" <<'EOF'
{"tag_name":"5.81.0","html_url":"https://github.com/RevenueCat/purchases-ios/releases/tag/5.81.0"}
EOF
cat >"${LATEST_REF}" <<'EOF'
{"object":{"sha":"f70991f77138907e5e930af98b37d36e1861e2c3","type":"tag"}}
EOF
cat >"${LATEST_TAG}" <<'EOF'
{"tag":"5.81.0","object":{"sha":"17e7dff140f119869d918de83d7a2136a990ef9b","type":"commit"}}
EOF

STALE_LOG="${TMP_DIR}/stale.log"
set +e
aipedometer_evaluate_revenuecat_staleness \
  "${PROJECT_FILE}" \
  "${CURRENT_TAG}" \
  "${LATEST_RELEASE}" \
  "${LATEST_REF}" \
  "${LATEST_TAG}" \
  >"${STALE_LOG}"
stale_status=$?
set -e

if [[ ${stale_status} -ne 10 ]]; then
  echo "Expected a stale RevenueCat pin to exit 10; got ${stale_status}." >&2
  exit 1
fi
grep -Fqx "status=stale" "${STALE_LOG}"
grep -Fqx "project_revision=72ab166846656b33a8d1a80c541cf7359e467f4d" "${STALE_LOG}"
grep -Fqx "current_version=5.78.0" "${STALE_LOG}"
grep -Fqx "current_commit=629a56ecef190469914b8f0914bf0446363eb09f" "${STALE_LOG}"
grep -Fqx "latest_version=5.81.0" "${STALE_LOG}"
grep -Fqx "latest_tag_object=f70991f77138907e5e930af98b37d36e1861e2c3" "${STALE_LOG}"
grep -Fqx "latest_commit=17e7dff140f119869d918de83d7a2136a990ef9b" "${STALE_LOG}"
grep -Fqx "mutation=none" "${STALE_LOG}"

sed -i '' 's/72ab166846656b33a8d1a80c541cf7359e467f4d/f70991f77138907e5e930af98b37d36e1861e2c3/' "${PROJECT_FILE}"
aipedometer_evaluate_revenuecat_staleness \
  "${PROJECT_FILE}" \
  "${LATEST_TAG}" \
  "${LATEST_RELEASE}" \
  "${LATEST_REF}" \
  "${LATEST_TAG}" \
  >"${TMP_DIR}/current.log"
grep -Fqx "status=current" "${TMP_DIR}/current.log"
grep -Fqx "mutation=none" "${TMP_DIR}/current.log"

LOCK_FILE="${TMP_DIR}/Package.resolved"
cat >"${LOCK_FILE}" <<'EOF'
{
  "pins": [
    {
      "identity": "purchases-ios-spm",
      "location": "https://github.com/RevenueCat/purchases-ios-spm",
      "state": {
        "branch": "f70991f77138907e5e930af98b37d36e1861e2c3",
        "revision": "17e7dff140f119869d918de83d7a2136a990ef9b"
      }
    }
  ],
  "version": 3
}
EOF
aipedometer_validate_revenuecat_resolved_commit \
  "${LOCK_FILE}" \
  "17e7dff140f119869d918de83d7a2136a990ef9b"

if aipedometer_validate_revenuecat_resolved_commit \
  "${LOCK_FILE}" \
  "3333333333333333333333333333333333333333" \
  >"${TMP_DIR}/mismatched-commit.log" 2>&1; then
  echo "Expected a peeled RevenueCat commit mismatch to fail." >&2
  exit 1
fi
grep -Fq "lockfile resolved commit does not match annotated tag" "${TMP_DIR}/mismatched-commit.log"

echo "check-revenuecat-staleness.sh tests passed."
