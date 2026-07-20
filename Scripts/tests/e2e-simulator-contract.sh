#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
E2E_SCRIPT="${ROOT_DIR}/Scripts/e2e-simulator.sh"

if rg -n '\$\{OUT_DIR\}/DerivedData' "${E2E_SCRIPT}" >/dev/null; then
  echo "E2E DerivedData must stay outside the artifact output directory." >&2
  exit 1
fi

if rg -n -- '-target AIPedometerWidgets' "${E2E_SCRIPT}" >/dev/null; then
  echo "The embedded widget must not be rebuilt after build-for-testing." >&2
  exit 1
fi

if ! rg -n 'aipedometer_prepare_simulator' "${E2E_SCRIPT}" >/dev/null; then
  echo "E2E must use the tested simulator boot-and-wait lifecycle." >&2
  exit 1
fi

if rg -n '^[[:space:]]*xcodebuild[[:space:]]' "${E2E_SCRIPT}" >/dev/null; then
  echo "Every E2E xcodebuild pipeline must use the stderr-capturing logged-command seam." >&2
  exit 1
fi

echo "e2e-simulator.sh contract tests passed."
