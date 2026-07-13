#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

python3 -m unittest "${ROOT_DIR}/Scripts/tests/test_xcresult_summary.py"
