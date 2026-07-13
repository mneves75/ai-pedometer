#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Uso: $0 <xcodebuild-log>" >&2
  exit 2
fi

RECOVERABLE_SIMULATOR_PATTERN='NSMachErrorDomain|server died|Failed to initialize for UI testing|Timed out waiting for AX loaded notification|Failed to get matching snapshots|AX loaded notification|kAXErrorAPIDisabled|Failed to get background assertion|Timed out while acquiring background assertion'

/usr/bin/grep -Eq -- "${RECOVERABLE_SIMULATOR_PATTERN}" "$1"
