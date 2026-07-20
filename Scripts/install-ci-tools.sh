#!/usr/bin/env bash
set -euo pipefail

readonly AIPEDOMETER_XCODEGEN_VERSION="2.46.0"
readonly AIPEDOMETER_AST_GREP_VERSION="0.44.1"
readonly AIPEDOMETER_RIPGREP_VERSION="15.2.0"
readonly AIPEDOMETER_ACTIONLINT_VERSION="1.7.12"
readonly AIPEDOMETER_SHELLCHECK_VERSION="0.11.0"

aipedometer_ci_tool_asset() {
  local tool="$1"
  local arch="$2"

  case "${arch}" in
    arm64 | x86_64) ;;
    *)
      echo "ERRO: arquitetura macOS nao suportada: ${arch}" >&2
      return 1
      ;;
  esac

  case "${tool}:${arch}" in
    xcodegen:arm64 | xcodegen:x86_64)
      printf '%s\n' "https://github.com/yonaskolb/XcodeGen/releases/download/${AIPEDOMETER_XCODEGEN_VERSION}/xcodegen.zip|4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806|zip|xcodegen/bin/xcodegen"
      ;;
    ast-grep:arm64)
      printf '%s\n' "https://github.com/ast-grep/ast-grep/releases/download/${AIPEDOMETER_AST_GREP_VERSION}/app-aarch64-apple-darwin.zip|0a2fef273b0ff1238b8307add911714f92021d25b919fa3ec9b6b2e046bb29cf|zip|ast-grep"
      ;;
    ast-grep:x86_64)
      printf '%s\n' "https://github.com/ast-grep/ast-grep/releases/download/${AIPEDOMETER_AST_GREP_VERSION}/app-x86_64-apple-darwin.zip|46584f3e4f67e9ae482de69e71e4e4aa88e68da322316fdd25ad73f2621ddbc5|zip|ast-grep"
      ;;
    ripgrep:arm64)
      printf '%s\n' "https://github.com/BurntSushi/ripgrep/releases/download/${AIPEDOMETER_RIPGREP_VERSION}/ripgrep-${AIPEDOMETER_RIPGREP_VERSION}-aarch64-apple-darwin.tar.gz|3750b2e93f37e0c692657da574d7019a101c0084da05a790c83fd335bad973e4|tar.gz|ripgrep-${AIPEDOMETER_RIPGREP_VERSION}-aarch64-apple-darwin/rg"
      ;;
    ripgrep:x86_64)
      printf '%s\n' "https://github.com/BurntSushi/ripgrep/releases/download/${AIPEDOMETER_RIPGREP_VERSION}/ripgrep-${AIPEDOMETER_RIPGREP_VERSION}-x86_64-apple-darwin.tar.gz|af7825fcc69a2afc7a7aea55fc9af90e26421d8f20fe59df32e233c0b8a231c1|tar.gz|ripgrep-${AIPEDOMETER_RIPGREP_VERSION}-x86_64-apple-darwin/rg"
      ;;
    actionlint:arm64)
      printf '%s\n' "https://github.com/rhysd/actionlint/releases/download/v${AIPEDOMETER_ACTIONLINT_VERSION}/actionlint_${AIPEDOMETER_ACTIONLINT_VERSION}_darwin_arm64.tar.gz|aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f|tar.gz|actionlint"
      ;;
    actionlint:x86_64)
      printf '%s\n' "https://github.com/rhysd/actionlint/releases/download/v${AIPEDOMETER_ACTIONLINT_VERSION}/actionlint_${AIPEDOMETER_ACTIONLINT_VERSION}_darwin_amd64.tar.gz|5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644|tar.gz|actionlint"
      ;;
    shellcheck:arm64)
      printf '%s\n' "https://github.com/koalaman/shellcheck/releases/download/v${AIPEDOMETER_SHELLCHECK_VERSION}/shellcheck-v${AIPEDOMETER_SHELLCHECK_VERSION}.darwin.aarch64.tar.gz|339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f|tar.gz|shellcheck-v${AIPEDOMETER_SHELLCHECK_VERSION}/shellcheck"
      ;;
    shellcheck:x86_64)
      printf '%s\n' "https://github.com/koalaman/shellcheck/releases/download/v${AIPEDOMETER_SHELLCHECK_VERSION}/shellcheck-v${AIPEDOMETER_SHELLCHECK_VERSION}.darwin.x86_64.tar.gz|c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51|tar.gz|shellcheck-v${AIPEDOMETER_SHELLCHECK_VERSION}/shellcheck"
      ;;
    *)
      echo "ERRO: ferramenta de CI nao suportada: ${tool}" >&2
      return 1
      ;;
  esac
}

aipedometer_verify_sha256() {
  local file="$1"
  local expected_sha="$2"

  if ! printf '%s  %s\n' "${expected_sha}" "${file}" | shasum -a 256 -c -; then
    echo "ERRO: checksum SHA-256 invalido para ${file}" >&2
    return 1
  fi
}

aipedometer_assert_tool_version() {
  local tool="$1"
  local binary="$2"
  local output
  local expected

  case "${tool}" in
    xcodegen)
      expected="Version: ${AIPEDOMETER_XCODEGEN_VERSION}"
      ;;
    ast-grep)
      expected="ast-grep ${AIPEDOMETER_AST_GREP_VERSION}"
      ;;
    ripgrep)
      expected="ripgrep ${AIPEDOMETER_RIPGREP_VERSION}"
      ;;
    actionlint)
      expected="${AIPEDOMETER_ACTIONLINT_VERSION}"
      ;;
    shellcheck)
      expected="version: ${AIPEDOMETER_SHELLCHECK_VERSION}"
      ;;
    *)
      echo "ERRO: ferramenta de CI nao suportada: ${tool}" >&2
      return 1
      ;;
  esac

  output="$("${binary}" --version 2>&1)" || {
    echo "ERRO: falha ao executar ${binary} --version" >&2
    return 1
  }
  if [[ "${tool}" == "shellcheck" ]]; then
    if [[ "${output}" == *"${expected}"* ]]; then
      return 0
    fi
    echo "ERRO: versao inesperada para ${tool}: esperado '${expected}'" >&2
    return 1
  fi

  output="${output%%$'\n'*}"

  if [[ "${tool}" == "ripgrep" && "${output}" =~ ^ripgrep[[:space:]]15\.2\.0([[:space:]]\(rev[[:space:]][0-9a-f]+\))?$ ]]; then
    return 0
  fi
  if [[ "${output}" != "${expected}" ]]; then
    echo "ERRO: versao inesperada para ${tool}: esperado '${expected}', recebido '${output}'" >&2
    return 1
  fi
}

aipedometer_require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERRO: comando obrigatorio ausente: ${command_name}" >&2
    return 1
  fi
}

aipedometer_install_ci_tools() {
  if [[ $# -eq 0 ]]; then
    echo "Uso: $0 <xcodegen|ast-grep|ripgrep|actionlint|shellcheck> [...]" >&2
    return 2
  fi
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "ERRO: instalacao de ferramentas suportada apenas no macOS" >&2
    return 1
  fi

  local required_command
  for required_command in curl mktemp shasum tar uname unzip; do
    aipedometer_require_command "${required_command}"
  done

  local arch
  arch="$(uname -m)"
  case "${arch}" in
    arm64 | x86_64) ;;
    *)
      echo "ERRO: arquitetura macOS nao suportada: ${arch}" >&2
      return 1
      ;;
  esac

  local temp_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
  local install_root
  install_root="$(mktemp -d "${temp_parent%/}/aipedometer-ci-tools.XXXXXX")"
  local bin_dir="${install_root}/bin"
  mkdir -p "${bin_dir}"

  local tool
  for tool in "$@"; do
    local asset_record
    local url
    local expected_sha
    local archive_type
    local member
    local archive
    local extract_dir
    local destination_name

    asset_record="$(aipedometer_ci_tool_asset "${tool}" "${arch}")"
    IFS='|' read -r url expected_sha archive_type member <<<"${asset_record}"
    archive="${install_root}/${url##*/}"
    extract_dir="${install_root}/extract-${tool}"
    mkdir -p "${extract_dir}"

    curl \
      --proto '=https' \
      --tlsv1.2 \
      --fail \
      --location \
      --silent \
      --show-error \
      --output "${archive}" \
      "${url}"
    aipedometer_verify_sha256 "${archive}" "${expected_sha}"

    case "${archive_type}" in
      zip)
        unzip -q "${archive}" -d "${extract_dir}"
        ;;
      tar.gz)
        tar -xzf "${archive}" -C "${extract_dir}"
        ;;
      *)
        echo "ERRO: formato de arquivo nao suportado: ${archive_type}" >&2
        return 1
        ;;
    esac

    if [[ ! -f "${extract_dir}/${member}" ]]; then
      echo "ERRO: executavel esperado ausente no arquivo: ${member}" >&2
      return 1
    fi

    case "${tool}" in
      xcodegen)
        destination_name="xcodegen"
        if [[ ! -d "${extract_dir}/xcodegen/share" ]]; then
          echo "ERRO: recursos esperados do XcodeGen estao ausentes" >&2
          return 1
        fi
        mkdir -p "${install_root}/share"
        cp -R "${extract_dir}/xcodegen/share/." "${install_root}/share/"
        ;;
      ast-grep)
        destination_name="ast-grep"
        ;;
      ripgrep)
        destination_name="rg"
        ;;
      actionlint)
        destination_name="actionlint"
        ;;
      shellcheck)
        destination_name="shellcheck"
        ;;
    esac

    cp "${extract_dir}/${member}" "${bin_dir}/${destination_name}"
    chmod 0755 "${bin_dir}/${destination_name}"
    aipedometer_assert_tool_version "${tool}" "${bin_dir}/${destination_name}"
  done

  if [[ -n "${GITHUB_PATH:-}" ]]; then
    printf '%s\n' "${bin_dir}" >>"${GITHUB_PATH}"
  fi
  printf 'CI_TOOLS_BIN=%s\n' "${bin_dir}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  aipedometer_install_ci_tools "$@"
fi
