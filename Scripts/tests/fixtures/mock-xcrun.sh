#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "${XCRUN_LOG}"
if [[ "$*" == *"device info apps"* ]] && [[ "$*" == *"--bundle-id"* ]]; then
  echo "$*"
fi
exit 0
