#!/usr/bin/env bash

# Selects the Xcode toolchain used by every build/test/install script.
#
# The project supports a RANGE of Xcode majors rather than a single hard pin. A hard pin on 26
# bricked every consuming script the moment the host upgraded to 27: the selector failed closed,
# so e2e-simulator.sh, install-on-device.sh and test-payments-device.sh all died at line 1 while
# the repository's own fast gates stayed green, because Scripts/tests/xcode-toolchain.sh exercises
# fixture directories rather than the host.
#
# A range is more forgiving than a pin but weaker as a reproducibility contract, so the selector
# always resolves and EXPORTS the exact version and build it chose. Record those in release
# evidence; "built on Xcode 27" is not attributable, "27.0 (27A266a)" is.
#
# Overrides, highest precedence first:
#   AIPEDOMETER_XCODE_DEVELOPER_DIR  hard pin to one Developer dir; validated, never bypassed
#   DEVELOPER_DIR                    honored when its major is supported
#   xcode-select -p                  the host default, honored when its major is supported
#   AIPEDOMETER_XCODE_FALLBACK       last resort (default /Applications/Xcode.app/Contents/Developer)
#   AIPEDOMETER_SUPPORTED_XCODE_MAJORS  space-separated majors (default "26 27")

aipedometer_xcode_version_line() {
  local developer_dir="$1"
  local version_output

  [[ -n "${developer_dir}" && -d "${developer_dir}" ]] || return 1
  version_output="$(DEVELOPER_DIR="${developer_dir}" xcodebuild -version 2>/dev/null)" || return 1
  printf '%s\n' "${version_output}"
}

# Prints "<version> <build>" when the directory holds a supported Xcode, else returns 1.
aipedometer_supported_xcode() {
  local developer_dir="$1"
  local supported_majors="${2:-${AIPEDOMETER_SUPPORTED_XCODE_MAJORS:-26 27}}"
  local version_output version_line build_line version build major

  version_output="$(aipedometer_xcode_version_line "${developer_dir}")" || return 1
  version_line="${version_output%%$'\n'*}"
  [[ "${version_line}" == Xcode\ * ]] || return 1
  version="${version_line#Xcode }"
  major="${version%%.*}"

  build_line="$(printf '%s\n' "${version_output}" | sed -n '2p')"
  build="${build_line#Build version }"
  [[ -n "${build}" ]] || build="unknown"

  # Explicit split: this file is sourced, and not every shell word-splits an unquoted parameter.
  local -a majors=()
  read -r -a majors <<<"${supported_majors}"
  local candidate
  for candidate in "${majors[@]}"; do
    if [[ "${major}" == "${candidate}" ]]; then
      printf '%s %s\n' "${version}" "${build}"
      return 0
    fi
  done

  return 1
}

aipedometer_select_xcode() {
  local supported_majors="${AIPEDOMETER_SUPPORTED_XCODE_MAJORS:-26 27}"
  local fallback_dir="${AIPEDOMETER_XCODE_FALLBACK:-/Applications/Xcode.app/Contents/Developer}"
  local pinned_dir="${AIPEDOMETER_XCODE_DEVELOPER_DIR:-}"
  local selected_dir="" resolved="" rejected=()
  local candidate_dir candidate_label

  # An explicit pin is absolute: if it is set and unusable, fail rather than silently drifting.
  if [[ -n "${pinned_dir}" ]]; then
    if resolved="$(aipedometer_supported_xcode "${pinned_dir}" "${supported_majors}")"; then
      selected_dir="${pinned_dir}"
    else
      echo "ERRO: AIPEDOMETER_XCODE_DEVELOPER_DIR=${pinned_dir} nao e um Xcode suportado (majors: ${supported_majors})." >&2
      return 1
    fi
  fi

  if [[ -z "${selected_dir}" ]]; then
    for candidate_label in DEVELOPER_DIR xcode-select AIPEDOMETER_XCODE_FALLBACK; do
      case "${candidate_label}" in
        DEVELOPER_DIR) candidate_dir="${DEVELOPER_DIR:-}" ;;
        xcode-select)
          candidate_dir=""
          if command -v xcode-select >/dev/null 2>&1; then
            candidate_dir="$(xcode-select -p 2>/dev/null)" || candidate_dir=""
          fi
          ;;
        AIPEDOMETER_XCODE_FALLBACK) candidate_dir="${fallback_dir}" ;;
      esac

      [[ -n "${candidate_dir}" ]] || continue

      if resolved="$(aipedometer_supported_xcode "${candidate_dir}" "${supported_majors}")"; then
        selected_dir="${candidate_dir}"
        break
      fi

      local seen_version
      seen_version="$(aipedometer_xcode_version_line "${candidate_dir}" 2>/dev/null | head -n 1)"
      rejected+=("${candidate_label}=${candidate_dir} (${seen_version:-nao e um Developer dir valido})")
    done
  fi

  if [[ -z "${selected_dir}" ]]; then
    echo "ERRO: nenhum Xcode suportado encontrado (majors aceitos: ${supported_majors})." >&2
    local entry
    for entry in "${rejected[@]}"; do
      echo "  rejeitado: ${entry}" >&2
    done
    echo "  Defina AIPEDOMETER_XCODE_DEVELOPER_DIR para um Xcode suportado, ou ajuste AIPEDOMETER_SUPPORTED_XCODE_MAJORS." >&2
    return 1
  fi

  export DEVELOPER_DIR="${selected_dir}"
  export AIPEDOMETER_RESOLVED_XCODE_VERSION="${resolved%% *}"
  export AIPEDOMETER_RESOLVED_XCODE_BUILD="${resolved#* }"
  echo "==> Xcode ${AIPEDOMETER_RESOLVED_XCODE_VERSION} (${AIPEDOMETER_RESOLVED_XCODE_BUILD}) selecionado: ${DEVELOPER_DIR}"
}
