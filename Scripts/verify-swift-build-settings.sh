#!/usr/bin/env bash
set -uo pipefail

# Fails when project.yml declares a SWIFT_* build setting that the selected Xcode does not define.
#
# Why this exists: project.yml once declared 20 SWIFT_UPCOMING_FEATURE_* settings, of which 16 were
# names Xcode has never defined (SWIFT_UPCOMING_FEATURE_SWIFT_6 instead of ..._6_0,
# ..._ISOLATED_DEFAULT_ARGUMENTS instead of ..._VALUES, and so on). Xcode ignores an unknown setting
# silently, so the file claimed twenty safety features while exactly one reached the compiler. It
# survived several audits because nothing executed it — a configuration no gate exercises drifts to
# fiction. This turns that into a check.
#
# Scope is deliberately narrow. Only the SWIFT_* family is validated, because those are declared in
# one authoritative place (Swift.xcspec). Settings from the Core/Clang specs are not checked here;
# widening this without an equally authoritative source would produce false positives, which is
# worse than no gate.
#
# Usage: bash Scripts/verify-swift-build-settings.sh [path/to/project.yml]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="${1:-${ROOT_DIR}/project.yml}"

if [[ ! -f "${PROJECT_FILE}" ]]; then
  echo "ERRO: arquivo de projeto nao encontrado: ${PROJECT_FILE}" >&2
  exit 1
fi

developer_dir="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
if [[ -z "${developer_dir}" || ! -d "${developer_dir}" ]]; then
  echo "ERRO: nenhum Xcode selecionado; defina DEVELOPER_DIR ou rode xcode-select." >&2
  exit 1
fi

# Swift.xcspec moved between Xcode versions; accept any copy under the selected Developer dir.
mapfile -t spec_files < <(find "${developer_dir}/.." -name 'Swift.xcspec' -type f 2>/dev/null)
if [[ "${#spec_files[@]}" -eq 0 ]]; then
  echo "ERRO: Swift.xcspec nao encontrado sob ${developer_dir}; nao da para validar." >&2
  echo "      Uma verificacao que nao encontra sua fonte deve falhar, nunca passar vazia." >&2
  exit 1
fi

known="$(rg -o --no-filename 'SWIFT_[A-Z0-9_]+' "${spec_files[@]}" 2>/dev/null | sort -u)"
if [[ -z "${known}" ]]; then
  echo "ERRO: nenhum nome SWIFT_* extraido de Swift.xcspec; extracao quebrada." >&2
  exit 1
fi

# Only the keys project.yml actually sets (a "KEY: value" line), never words inside comments.
declared="$(rg -o '^\s*(SWIFT_[A-Z0-9_]+)\s*:' --replace '$1' "${PROJECT_FILE}" 2>/dev/null | sort -u)"

unknown=()
while IFS= read -r setting; do
  [[ -n "${setting}" ]] || continue
  # SWIFT_VERSION and a few well-known keys live outside Swift.xcspec in some Xcode layouts.
  case "${setting}" in
    SWIFT_VERSION|SWIFT_COMPILATION_MODE|SWIFT_EMIT_LOC_STRINGS|SWIFT_TREAT_WARNINGS_AS_ERRORS) continue ;;
  esac
  if ! printf '%s\n' "${known}" | grep -qx "${setting}"; then
    unknown+=("${setting}")
  fi
done <<<"${declared}"

if [[ "${#unknown[@]}" -gt 0 ]]; then
  echo "ERRO: ${PROJECT_FILE} declara SWIFT_* que este Xcode nao define (serao ignorados silenciosamente):" >&2
  for setting in "${unknown[@]}"; do
    echo "  - ${setting}" >&2
  done
  echo "      Confira o nome em Swift.xcspec antes de reintroduzir." >&2
  exit 1
fi

count="$(printf '%s\n' "${declared}" | grep -c . || true)"
echo "OK: ${count} configuracao(oes) SWIFT_* em $(basename "${PROJECT_FILE}") existem neste Xcode."
