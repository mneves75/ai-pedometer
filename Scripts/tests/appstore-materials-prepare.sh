#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/package/screenshots/iphone_69" "${TMP_DIR}/ipad" "${TMP_DIR}/iphone"
for label in Dashboard 'AI Coach' Workouts 'Training Plans' History Badges 'Active Workout' 'About - Tip Jar'; do
  printf 'owned test capture\n' > "${TMP_DIR}/iphone/${label}_test.png"
  cp "${TMP_DIR}/iphone/${label}_test.png" "${TMP_DIR}/package/screenshots/iphone_69/${label}_test.png"
done
for label in 'Onboarding - Welcome' 'Onboarding - Goal' 'Onboarding - Permissions'; do
  printf 'owned test capture\n' > "${TMP_DIR}/ipad/${label}_test.png"
done

expect_preserved_overlap() {
  local source="$1"
  if bash "${ROOT_DIR}/Scripts/appstore-materials-prepare.sh" \
      --iphone-src "${source}" --ipad-src "${TMP_DIR}/ipad" --out-dir "${TMP_DIR}/package" \
      > "${TMP_DIR}/overlap.log" 2>&1; then
    echo 'Expected overlapping screenshot paths to fail.' >&2
    exit 1
  fi
  if [[ ! -f "${TMP_DIR}/package/screenshots/iphone_69/Dashboard_test.png" ]]; then
    echo 'Screenshot preparation deleted its input capture.' >&2
    exit 1
  fi
}

expect_preserved_overlap "${TMP_DIR}/package/screenshots/iphone_69"
ln -s "${TMP_DIR}/package/screenshots/iphone_69" "${TMP_DIR}/alias"
expect_preserved_overlap "${TMP_DIR}/alias"

# Incomplete input must not erase an existing package, even when paths are disjoint.
rm "${TMP_DIR}/iphone/Dashboard_test.png"
if bash "${ROOT_DIR}/Scripts/appstore-materials-prepare.sh" \
    --iphone-src "${TMP_DIR}/iphone" --ipad-src "${TMP_DIR}/ipad" --out-dir "${TMP_DIR}/package" \
    > "${TMP_DIR}/missing.log" 2>&1; then
  echo 'Expected incomplete screenshot input to fail.' >&2
  exit 1
fi
test -f "${TMP_DIR}/package/screenshots/iphone_69/Dashboard_test.png"

# A symlinked output must never redirect cleanup outside the selected package.
mkdir -p "${TMP_DIR}/escaped-package/screenshots" "${TMP_DIR}/external"
printf 'owned sentinel\n' > "${TMP_DIR}/external/sentinel.png"
ln -s "${TMP_DIR}/external" "${TMP_DIR}/escaped-package/screenshots/iphone_65"
if bash "${ROOT_DIR}/Scripts/appstore-materials-prepare.sh" \
    --iphone-src "${TMP_DIR}/package/screenshots/iphone_69" --ipad-src "${TMP_DIR}/ipad" --out-dir "${TMP_DIR}/escaped-package" \
    > "${TMP_DIR}/escape.log" 2>&1; then
  echo 'Expected escaping output symlink to fail.' >&2
  exit 1
fi
test -f "${TMP_DIR}/external/sentinel.png"

# Positive control: the complete, disjoint input reaches image conversion.
mkdir -p "${TMP_DIR}/bin"
cat > "${TMP_DIR}/bin/sips" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
test "$1" = '-z'
test "$2" = '2778'
test "$3" = '1284'
test -f "$4"
if [[ "${FAIL_CONVERSION:-0}" == '1' ]]; then exit 7; fi
MOCK
chmod +x "${TMP_DIR}/bin/sips"

# A failed conversion must leave the previously prepared package intact.
mkdir -p "${TMP_DIR}/valid-package/screenshots/iphone_65"
printf 'previous package\n' > "${TMP_DIR}/valid-package/screenshots/iphone_65/sentinel.png"
printf 'previous readme\n' > "${TMP_DIR}/valid-package/README.md"
if FAIL_CONVERSION=1 PATH="${TMP_DIR}/bin:${PATH}" bash "${ROOT_DIR}/Scripts/appstore-materials-prepare.sh" \
    --iphone-src "${TMP_DIR}/package/screenshots/iphone_69" --ipad-src "${TMP_DIR}/ipad" --out-dir "${TMP_DIR}/valid-package" \
    > "${TMP_DIR}/conversion-failure.log" 2>&1; then
  echo 'Expected image conversion failure.' >&2
  exit 1
fi
test "$(cat "${TMP_DIR}/valid-package/screenshots/iphone_65/sentinel.png")" = 'previous package'
test "$(cat "${TMP_DIR}/valid-package/README.md")" = 'previous readme'

PATH="${TMP_DIR}/bin:${PATH}" bash "${ROOT_DIR}/Scripts/appstore-materials-prepare.sh" \
    --iphone-src "${TMP_DIR}/package/screenshots/iphone_69" --ipad-src "${TMP_DIR}/ipad" --out-dir "${TMP_DIR}/valid-package" \
    > "${TMP_DIR}/valid.log" 2>&1
test "$(find "${TMP_DIR}/valid-package/screenshots" -name '*.png' -type f | wc -l | tr -d ' ')" = '19'
test -f "${TMP_DIR}/valid-package/README.md"

echo 'Screenshot input preservation tests passed.'
