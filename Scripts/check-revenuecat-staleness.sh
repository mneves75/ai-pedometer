#!/usr/bin/env bash
set -euo pipefail

readonly AIPEDOMETER_REVENUECAT_SPM_URL="https://github.com/RevenueCat/purchases-ios-spm"
readonly AIPEDOMETER_GITHUB_API="https://api.github.com"

aipedometer_json_value() {
  local json_file="$1"
  local dotted_path="$2"

  python3 - "${json_file}" "${dotted_path}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)

for component in sys.argv[2].split("."):
    value = value[component]

if not isinstance(value, str):
    raise TypeError(f"Expected string at {sys.argv[2]}")
print(value)
PY
}

aipedometer_project_revenuecat_revision() {
  local project_file="$1"
  awk -v expected_url="${AIPEDOMETER_REVENUECAT_SPM_URL}" '
    $1 == "url:" && $2 == expected_url { in_revenuecat = 1; next }
    in_revenuecat && $1 == "revision:" { print $2; exit }
    in_revenuecat && /^[^[:space:]]/ { in_revenuecat = 0 }
  ' "${project_file}"
}

aipedometer_validate_sha() {
  local label="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^[0-9a-f]{40}$ ]]; then
    echo "ERRO: ${label} nao e um SHA Git completo: ${value}" >&2
    return 1
  fi
}

aipedometer_validate_version() {
  local label="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERRO: ${label} nao e uma versao RevenueCat valida: ${value}" >&2
    return 1
  fi
}

aipedometer_validate_revenuecat_resolved_commit() {
  local lock_file="$1"
  local expected_commit="$2"

  aipedometer_validate_sha "expected_commit" "${expected_commit}"
  if [[ ! -f "${lock_file}" ]]; then
    echo "ERRO: Package.resolved nao encontrado: ${lock_file}" >&2
    return 1
  fi

  python3 - "${lock_file}" "${expected_commit}" <<'PY'
import json
import sys

lock_file, expected_commit = sys.argv[1:]
with open(lock_file, encoding="utf-8") as handle:
    lock = json.load(handle)

pins = [
    pin
    for pin in lock.get("pins", [])
    if pin.get("identity") == "purchases-ios-spm"
    and pin.get("location") == "https://github.com/RevenueCat/purchases-ios-spm"
]
if len(pins) != 1:
    print("ERRO: lockfile must contain exactly one RevenueCat pin", file=sys.stderr)
    raise SystemExit(1)

resolved_commit = (pins[0].get("state") or {}).get("revision")
if resolved_commit != expected_commit:
    print(
        "ERRO: lockfile resolved commit does not match annotated tag",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

aipedometer_evaluate_revenuecat_staleness() {
  local project_file="$1"
  local current_tag_json="$2"
  local latest_release_json="$3"
  local latest_ref_json="$4"
  local latest_tag_json="$5"

  local project_revision
  local current_version
  local current_commit
  local current_object_type
  local latest_version
  local latest_url
  local latest_tag_object
  local latest_ref_type
  local latest_tag_version
  local latest_commit
  local latest_object_type

  project_revision="$(aipedometer_project_revenuecat_revision "${project_file}")"
  current_version="$(aipedometer_json_value "${current_tag_json}" tag)"
  current_commit="$(aipedometer_json_value "${current_tag_json}" object.sha)"
  current_object_type="$(aipedometer_json_value "${current_tag_json}" object.type)"
  latest_version="$(aipedometer_json_value "${latest_release_json}" tag_name)"
  latest_url="$(aipedometer_json_value "${latest_release_json}" html_url)"
  latest_tag_object="$(aipedometer_json_value "${latest_ref_json}" object.sha)"
  latest_ref_type="$(aipedometer_json_value "${latest_ref_json}" object.type)"
  latest_tag_version="$(aipedometer_json_value "${latest_tag_json}" tag)"
  latest_commit="$(aipedometer_json_value "${latest_tag_json}" object.sha)"
  latest_object_type="$(aipedometer_json_value "${latest_tag_json}" object.type)"

  aipedometer_validate_sha "project_revision" "${project_revision}"
  aipedometer_validate_sha "current_commit" "${current_commit}"
  aipedometer_validate_sha "latest_tag_object" "${latest_tag_object}"
  aipedometer_validate_sha "latest_commit" "${latest_commit}"
  aipedometer_validate_version "current_version" "${current_version}"
  aipedometer_validate_version "latest_version" "${latest_version}"

  if [[ "${current_object_type}" != "commit" ]]; then
    echo "ERRO: o pin atual nao aponta para um tag anotado que resolve em commit" >&2
    return 1
  fi
  if [[ "${latest_ref_type}" != "tag" ]]; then
    echo "ERRO: o release RevenueCat mais recente nao usa um tag anotado" >&2
    return 1
  fi
  if [[ "${latest_object_type}" != "commit" || "${latest_tag_version}" != "${latest_version}" ]]; then
    echo "ERRO: o tag RevenueCat mais recente nao resolve no release consultado" >&2
    return 1
  fi

  if [[ "${project_revision}" == "${latest_tag_object}" ]]; then
    printf 'status=current\n'
  else
    printf 'status=stale\n'
  fi
  printf 'project_revision=%s\n' "${project_revision}"
  printf 'current_version=%s\n' "${current_version}"
  printf 'current_commit=%s\n' "${current_commit}"
  printf 'latest_version=%s\n' "${latest_version}"
  printf 'latest_tag_object=%s\n' "${latest_tag_object}"
  printf 'latest_commit=%s\n' "${latest_commit}"
  printf 'latest_url=%s\n' "${latest_url}"
  printf 'mutation=none\n'

  if [[ "${project_revision}" != "${latest_tag_object}" ]]; then
    return 10
  fi
}

aipedometer_github_get() {
  local url="$1"
  local output_file="$2"
  local curl_args=(
    --proto '=https'
    --tlsv1.2
    --fail
    --location
    --silent
    --show-error
    --header "Accept: application/vnd.github+json"
    --header "X-GitHub-Api-Version: 2022-11-28"
  )

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(--header "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl "${curl_args[@]}" "${url}" >"${output_file}"
}

aipedometer_check_revenuecat_staleness() {
  local project_file="${1:-}"
  local lock_file="${2:-}"
  if [[ -z "${project_file}" ]]; then
    project_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/project.yml"
  fi
  if [[ -z "${lock_file}" ]]; then
    lock_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/AIPedometer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  fi
  if [[ ! -f "${project_file}" ]]; then
    echo "ERRO: project.yml nao encontrado: ${project_file}" >&2
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "ERRO: curl e python3 sao obrigatorios" >&2
    return 1
  fi

  local project_revision
  project_revision="$(aipedometer_project_revenuecat_revision "${project_file}")"
  aipedometer_validate_sha "project_revision" "${project_revision}"

  local temp_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
  local temp_dir
  temp_dir="$(mktemp -d "${temp_parent%/}/aipedometer-revenuecat.XXXXXX")"
  trap 'rm -rf "${temp_dir}"' RETURN

  local current_tag_json="${temp_dir}/current-tag.json"
  local latest_release_json="${temp_dir}/latest-release.json"
  local latest_ref_json="${temp_dir}/latest-ref.json"
  local latest_tag_json="${temp_dir}/latest-tag.json"

  aipedometer_github_get \
    "${AIPEDOMETER_GITHUB_API}/repos/RevenueCat/purchases-ios-spm/git/tags/${project_revision}" \
    "${current_tag_json}"
  aipedometer_github_get \
    "${AIPEDOMETER_GITHUB_API}/repos/RevenueCat/purchases-ios/releases/latest" \
    "${latest_release_json}"

  local latest_version
  latest_version="$(aipedometer_json_value "${latest_release_json}" tag_name)"
  aipedometer_validate_version "latest_version" "${latest_version}"
  aipedometer_github_get \
    "${AIPEDOMETER_GITHUB_API}/repos/RevenueCat/purchases-ios-spm/git/ref/tags/${latest_version}" \
    "${latest_ref_json}"

  local latest_tag_object
  latest_tag_object="$(aipedometer_json_value "${latest_ref_json}" object.sha)"
  aipedometer_validate_sha "latest_tag_object" "${latest_tag_object}"
  aipedometer_github_get \
    "${AIPEDOMETER_GITHUB_API}/repos/RevenueCat/purchases-ios-spm/git/tags/${latest_tag_object}" \
    "${latest_tag_json}"

  local current_commit
  current_commit="$(aipedometer_json_value "${current_tag_json}" object.sha)"
  aipedometer_validate_revenuecat_resolved_commit "${lock_file}" "${current_commit}"

  local status
  set +e
  aipedometer_evaluate_revenuecat_staleness \
    "${project_file}" \
    "${current_tag_json}" \
    "${latest_release_json}" \
    "${latest_ref_json}" \
    "${latest_tag_json}"
  status=$?
  set -e
  return "${status}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  aipedometer_check_revenuecat_staleness "$@"
fi
