#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOCAL_AGENTS="${LOCAL_AGENTS:-${ROOT_DIR}/AGENTS.md}"
GUIDELINES_REF_ROOT="${GUIDELINES_REF_ROOT:-${HOME}/dev/GUIDELINES-REF}"
UPSTREAM_AGENTS="${GUIDELINES_REF_ROOT}/AGENTS.md"

if [[ ! -f "${LOCAL_AGENTS}" ]]; then
  echo "AGENTS.md not found at ${LOCAL_AGENTS}" >&2
  exit 1
fi

if [[ ! -f "${UPSTREAM_AGENTS}" ]]; then
  echo "GUIDELINES-REF AGENTS.md not found at ${UPSTREAM_AGENTS}" >&2
  echo "Set GUIDELINES_REF_ROOT to override the location." >&2
  exit 1
fi

local_section="$(
  awk '
    found { print }
    /^## GUIDELINES-REF/ { found = 1; next }
  ' "${LOCAL_AGENTS}"
)"

if [[ -z "${local_section}" ]]; then
  echo "Failed to locate ## GUIDELINES-REF section in ${LOCAL_AGENTS}" >&2
  exit 1
fi

if [[ "${local_section}" == Synced\ from* ]]; then
  local_section="$(printf "%s\n" "${local_section}" | tail -n +2)"
fi

local_section="$(printf "%s\n" "${local_section}" | awk 'BEGIN{skip=1} { if (skip && $0=="") next; skip=0; print }')"

upstream_section="$(
  tail -n +2 "${UPSTREAM_AGENTS}" | awk 'BEGIN{skip=1} { if (skip && $0=="") next; skip=0; print }'
)"

if ! diff -u <(printf "%s\n" "${upstream_section}") <(printf "%s\n" "${local_section}"); then
  echo "" >&2
  echo "AGENTS.md GUIDELINES-REF section is out of sync with ${UPSTREAM_AGENTS}" >&2
  exit 1
fi

echo "AGENTS.md GUIDELINES-REF section is in sync with ${UPSTREAM_AGENTS}"
