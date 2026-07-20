#!/usr/bin/env bash

aipedometer_xcode_26_version() {
  local developer_dir="$1"
  local version_output
  local version_line

  [[ -d "${developer_dir}" ]] || return 1
  version_output="$(DEVELOPER_DIR="${developer_dir}" xcodebuild -version 2>/dev/null)" || return 1
  version_line="${version_output%%$'\n'*}"

  if [[ "${version_line}" == "Xcode 26" || "${version_line}" == "Xcode 26."* ]]; then
    printf '%s\n' "${version_line#Xcode }"
    return 0
  fi

  return 1
}

aipedometer_select_xcode_26() {
  local requested_dir="${DEVELOPER_DIR:-}"
  local selected_by_xcode_select=""
  local fallback_dir="${AIPEDOMETER_XCODE_26_FALLBACK:-/Applications/Xcode.app/Contents/Developer}"
  local selected_dir=""
  local selected_version=""

  if [[ -n "${requested_dir}" ]]; then
    selected_version="$(aipedometer_xcode_26_version "${requested_dir}")" || selected_version=""
    if [[ -n "${selected_version}" ]]; then
      selected_dir="${requested_dir}"
    fi
  fi

  if [[ -z "${selected_dir}" ]] && command -v xcode-select >/dev/null 2>&1; then
    selected_by_xcode_select="$(xcode-select -p 2>/dev/null)" || selected_by_xcode_select=""
    if [[ -n "${selected_by_xcode_select}" ]]; then
      selected_version="$(aipedometer_xcode_26_version "${selected_by_xcode_select}")" || selected_version=""
      if [[ -n "${selected_version}" ]]; then
        selected_dir="${selected_by_xcode_select}"
      fi
    fi
  fi

  if [[ -z "${selected_dir}" ]]; then
    selected_version="$(aipedometer_xcode_26_version "${fallback_dir}")" || selected_version=""
    if [[ -n "${selected_version}" ]]; then
      selected_dir="${fallback_dir}"
    fi
  fi

  if [[ -z "${selected_dir}" ]]; then
    echo "ERRO: Xcode 26.x nao encontrado. Instale o Xcode 26 em /Applications/Xcode.app ou defina DEVELOPER_DIR para um Xcode 26.x valido." >&2
    return 1
  fi

  export DEVELOPER_DIR="${selected_dir}"
  echo "==> Xcode ${selected_version} selecionado: ${DEVELOPER_DIR}"
}
