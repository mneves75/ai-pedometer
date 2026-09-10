#!/usr/bin/env bash
set -uo pipefail

# Answers one question before an agent or a human spends twenty minutes on a doomed build:
# "can I actually build, test and verify in this checkout, on this host, right now?"
#
# This exists because the repository's fast gates were all green while the toolchain selector was
# dead on the host: Scripts/tests/*.sh exercise fixtures, so nothing checked the machine. It also
# folds in the environment readings docs/agents/testing.md asks for but never enforced (free disk,
# resolved Xcode, current commit).
#
# Usage:
#   bash Scripts/preflight.sh              environment checks + the ~2s fast gate tier
#   bash Scripts/preflight.sh --with-tests also run the shell regression suite (~25s)
#   bash Scripts/preflight.sh --quiet      only failures and the summary
#
# Exit 0 = everything required is present. Exit 1 = at least one REQUIRED check failed.
# WARN never fails the run; it flags something that will bite later (low disk before an archive).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}" || exit 1

WITH_TESTS=0
QUIET=0
for arg in "$@"; do
  case "${arg}" in
    --with-tests) WITH_TESTS=1 ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '3,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Argumento desconhecido: ${arg}" >&2; exit 2 ;;
  esac
done

# Free space below this is not enough for a Debug DerivedData tree (~1.1 GiB) plus an archive.
MIN_FREE_GIB="${AIPEDOMETER_MIN_FREE_GIB:-20}"

FAILURES=0
WARNINGS=0

say() { [[ "${QUIET}" -eq 1 ]] || printf '%s\n' "$*"; }
pass() { [[ "${QUIET}" -eq 1 ]] || printf '  \033[32mOK\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }

say "== Ambiente =="

# --- Toolchain ---------------------------------------------------------------------------------
# shellcheck source=Scripts/lib/xcode-toolchain.sh
if source "${ROOT_DIR}/Scripts/lib/xcode-toolchain.sh" 2>/dev/null; then
  if toolchain_line="$(aipedometer_select_xcode 2>&1)"; then
    pass "${toolchain_line#==> }"
  else
    fail "Nenhum Xcode suportado. Detalhe:"
    printf '%s\n' "${toolchain_line}" | sed 's/^/          /'
  fi
else
  fail "Scripts/lib/xcode-toolchain.sh nao pode ser carregado."
fi

# --- Disk --------------------------------------------------------------------------------------
free_gib="$(df -g . 2>/dev/null | awk 'NR==2 {print $4}')"
if [[ -n "${free_gib}" ]]; then
  if [[ "${free_gib}" -lt "${MIN_FREE_GIB}" ]]; then
    warn "Apenas ${free_gib} GiB livres (minimo recomendado ${MIN_FREE_GIB} GiB). Um archive pode falhar no meio."
  else
    pass "Espaco livre: ${free_gib} GiB"
  fi
else
  warn "Nao foi possivel ler o espaco livre em disco."
fi

# --- Required tools --------------------------------------------------------------------------
for tool in xcodegen ast-grep rg; do
  if command -v "${tool}" >/dev/null 2>&1; then
    pass "${tool} presente"
  else
    fail "${tool} ausente (necessario). Rode: bash Scripts/install-ci-tools.sh"
  fi
done
for tool in actionlint shellcheck; do
  if command -v "${tool}" >/dev/null 2>&1; then
    pass "${tool} presente"
  else
    warn "${tool} ausente — o lint correspondente sera pulado localmente, mas roda no CI."
  fi
done

# --- Checkout ----------------------------------------------------------------------------------
hooks_path="$(git config --get core.hooksPath 2>/dev/null || true)"
if [[ "${hooks_path}" == ".githooks" ]]; then
  pass "core.hooksPath=.githooks"
else
  fail "core.hooksPath='${hooks_path:-<unset>}'. Rode: git config core.hooksPath .githooks"
fi

if [[ -f Config/Local.xcconfig ]]; then
  pass "Config/Local.xcconfig presente"
else
  warn "Config/Local.xcconfig ausente (nao versionado). Builds assinados e RevenueCat vao falhar; copie de Config/Local.xcconfig.example."
fi

if [[ -f AIPedometer.xcodeproj/project.pbxproj ]]; then
  pass "AIPedometer.xcodeproj gerado"
else
  fail "AIPedometer.xcodeproj ausente. Rode: xcodegen generate"
fi

say "  ----  commit: $(git rev-parse --short HEAD 2>/dev/null || echo '?')  branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

booted="$(xcrun simctl list devices booted 2>/dev/null | grep -c 'Booted' || true)"
say "  ----  simuladores booted: ${booted:-0} (serialize jobs; nao use um simulador de outra sessao)"

# --- Fast gates --------------------------------------------------------------------------------
say ""
say "== Gates rapidos =="

GATE_LOG="$(mktemp -t aip-preflight-gate)"
trap 'rm -f "${GATE_LOG}"' EXIT

gate() {
  local label="$1"; shift
  if "$@" >"${GATE_LOG}" 2>&1; then
    pass "${label}"
  else
    fail "${label}"
    tail -6 "${GATE_LOG}" | sed 's/^/          /'
  fi
}

command -v ast-grep >/dev/null 2>&1 && gate "ast-grep scan" ast-grep scan --config sgconfig.yml
command -v actionlint >/dev/null 2>&1 && gate "actionlint" actionlint
gate "check-agents-sync.sh" bash Scripts/check-agents-sync.sh
gate "verify-device-identifiers.sh" bash Scripts/verify-device-identifiers.sh
gate "verify-entitlements.sh" bash Scripts/verify-entitlements.sh
gate "verify-revenuecat-lock.sh" bash Scripts/verify-revenuecat-lock.sh

if [[ "${WITH_TESTS}" -eq 1 ]]; then
  say ""
  say "== Suite de scripts =="
  for test_script in Scripts/tests/*.sh; do
    gate "$(basename "${test_script}")" bash "${test_script}"
  done
fi

say ""
if [[ "${FAILURES}" -gt 0 ]]; then
  printf '\033[31m%s\033[0m\n' "PREFLIGHT FALHOU: ${FAILURES} problema(s), ${WARNINGS} aviso(s)."
  exit 1
fi
printf '\033[32m%s\033[0m\n' "PREFLIGHT OK (${WARNINGS} aviso(s))."
