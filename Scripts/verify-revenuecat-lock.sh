#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="${1:-${ROOT_DIR}/project.yml}"
PBXPROJ_FILE="${2:-${ROOT_DIR}/AIPedometer.xcodeproj/project.pbxproj}"
LOCK_FILE="${3:-${ROOT_DIR}/AIPedometer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved}"

for required_file in "${PROJECT_FILE}" "${PBXPROJ_FILE}" "${LOCK_FILE}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "ERRO: arquivo obrigatorio ausente: ${required_file}" >&2
    exit 1
  fi
done

python3 - "${PROJECT_FILE}" "${PBXPROJ_FILE}" "${LOCK_FILE}" <<'PY'
import json
import re
import sys
from pathlib import Path

EXPECTED_URL = "https://github.com/RevenueCat/purchases-ios-spm"
EXPECTED_IDENTITY = "purchases-ios-spm"
SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")


def fail(message: str) -> None:
    print(f"ERRO: {message}", file=sys.stderr)
    raise SystemExit(1)


project_path, pbxproj_path, lock_path = map(Path, sys.argv[1:])
project_lines = project_path.read_text(encoding="utf-8").splitlines()

declared_revision = ""
for index, line in enumerate(project_lines):
    if line.strip() != f"url: {EXPECTED_URL}":
        continue
    for candidate in project_lines[index + 1 :]:
        stripped = candidate.strip()
        if stripped.startswith("revision:"):
            declared_revision = stripped.removeprefix("revision:").strip().strip('"\'')
            break
        if candidate and not candidate[0].isspace():
            break
    break

if not SHA_PATTERN.fullmatch(declared_revision):
    fail("project.yml RevenueCat revision is not a full Git SHA")

pbxproj = pbxproj_path.read_text(encoding="utf-8")
package_blocks = re.findall(
    r"\{\s*isa = XCRemoteSwiftPackageReference;.*?\n\s*\};",
    pbxproj,
    flags=re.DOTALL,
)
revenuecat_blocks = [block for block in package_blocks if f'repositoryURL = "{EXPECTED_URL}";' in block]
if len(revenuecat_blocks) != 1:
    fail("generated project must contain exactly one RevenueCat package reference")

revenuecat_block = revenuecat_blocks[0]
if not re.search(r"\bkind = revision;", revenuecat_block):
    fail("generated project RevenueCat requirement is not an immutable revision")
pbx_revision_match = re.search(r"\brevision = ([0-9a-f]{40});", revenuecat_block)
if pbx_revision_match is None:
    fail("generated project RevenueCat revision is not a full Git SHA")
if pbx_revision_match.group(1) != declared_revision:
    fail("generated project revision does not match project.yml")

try:
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    fail(f"Package.resolved is not valid JSON: {error}")

pins = [
    pin
    for pin in lock.get("pins", [])
    if pin.get("identity") == EXPECTED_IDENTITY or pin.get("location") == EXPECTED_URL
]
if len(pins) != 1:
    fail("Package.resolved must contain exactly one RevenueCat pin")

pin = pins[0]
if pin.get("identity") != EXPECTED_IDENTITY or pin.get("location") != EXPECTED_URL:
    fail("Package.resolved RevenueCat identity or location is inconsistent")
state = pin.get("state") or {}

# Xcode 26 serializes a revision requirement that names an annotated-tag object
# as state.branch=<declared tag object SHA>, while state.revision holds the
# peeled commit. Both values are intentional and must not be forced equal.
if state.get("branch") != declared_revision:
    fail("lockfile branch does not match project.yml annotated-tag revision")
resolved_revision = state.get("revision", "")
if not isinstance(resolved_revision, str) or not SHA_PATTERN.fullmatch(resolved_revision):
    fail("lockfile revision is not a full Git SHA")

print("RevenueCat dependency lock is coherent.")
PY
