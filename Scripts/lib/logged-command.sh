#!/usr/bin/env bash

aipedometer_run_logged() {
  local log_file="$1"
  shift

  (
    set -o pipefail
    "$@" 2>&1 | tee "${log_file}"
  )
}
