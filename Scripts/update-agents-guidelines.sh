#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOCAL_AGENTS="${LOCAL_AGENTS:-${ROOT_DIR}/AGENTS.md}"
GUIDELINES_REF_ROOT="${GUIDELINES_REF_ROOT:-${HOME}/dev/GUIDELINES-REF}"
UPSTREAM_AGENTS="${GUIDELINES_REF_ROOT}/AGENTS.md"
SYNC_NOTICE="${SYNC_NOTICE:-Synced from \`~/dev/GUIDELINES-REF/AGENTS.md\` (use \`bash Scripts/check-agents-sync.sh\`).}"

if [[ ! -f "${LOCAL_AGENTS}" ]]; then
  echo "AGENTS.md not found at ${LOCAL_AGENTS}" >&2
  exit 1
fi

if [[ ! -f "${UPSTREAM_AGENTS}" ]]; then
  echo "GUIDELINES-REF AGENTS.md not found at ${UPSTREAM_AGENTS}" >&2
  echo "Set GUIDELINES_REF_ROOT to override the location." >&2
  exit 1
fi

prefix="$(
  awk '
    { print }
    /^## GUIDELINES-REF/ { exit }
  ' "${LOCAL_AGENTS}"
)"

if [[ -z "${prefix}" ]]; then
  echo "Failed to locate ## GUIDELINES-REF section in ${LOCAL_AGENTS}" >&2
  exit 1
fi

upstream_section="$(
  tail -n +2 "${UPSTREAM_AGENTS}" | awk 'BEGIN{skip=1} { if (skip && $0=="") next; skip=0; print }'
)"

tmp_file="$(mktemp)"
printf "%s\n" "${prefix}" > "${tmp_file}"
printf "%s\n" "${SYNC_NOTICE}" >> "${tmp_file}"
printf "%s\n" "${upstream_section}" >> "${tmp_file}"

mv "${tmp_file}" "${LOCAL_AGENTS}"
echo "Updated ${LOCAL_AGENTS} from ${UPSTREAM_AGENTS}"
