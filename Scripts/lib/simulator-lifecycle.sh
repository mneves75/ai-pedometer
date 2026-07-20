#!/usr/bin/env bash

aipedometer_prepare_simulator() {
  local udid="$1"
  local erase_simulator="${2:-0}"

  if [[ -z "${udid}" ]]; then
    echo "ERRO: UDID de simulador vazio." >&2
    return 1
  fi

  if [[ "${erase_simulator}" == "1" ]]; then
    xcrun simctl shutdown "${udid}" >/dev/null 2>&1 || true
    xcrun simctl erase "${udid}" >/dev/null
  fi

  xcrun simctl boot "${udid}" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "${udid}" -b >/dev/null
}
