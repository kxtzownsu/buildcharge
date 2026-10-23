#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}"/lib/common.sh
[[ "${VERBOSE}" == 1 ]] && set -x

# usage: parse-manifest.sh <manifest.json> <toolchain-> <target arch> <package dir>
MANIFEST_JSON="$1"
CROSS_COMPILER_TOOLCHAIN="$2"
TARGET_ARCH="$3"
PACKAGE_DIR="$4"
OUT_FILE="/tmp/manifest.json"

require_arg "$MANIFEST_JSON" "manifest json"
require_arg "$CROSS_COMPILER_TOOLCHAIN" "cross compiler toolchain"
require_arg "$TARGET_ARCH" "target arch"
require_arg "$PACKAGE_DIR" "package directory"

PACKAGE_DIR="/${PACKAGE_DIR#/}"
PACKAGE_DIR="${PACKAGE_DIR%/}"

command -v jq >/dev/null 2>&1 || error 1 "jq is required"
command -v envsubst >/dev/null 2>&1 || error 1 "envsubst is required"
[[ ! -f "$MANIFEST_JSON" ]] && error 1 "manifest not found: $MANIFEST_JSON"

case "$TARGET_ARCH" in
  x86_64|aarch64) ;;
  *) error 1 "unsupported arch: $TARGET_ARCH" ;;
esac

init_global_vars() {
  local host_arch cores bindir tool_prefix root

  host_arch="$(uname -m)"
  cores="$(nproc)"
  [[ "${USE_ALL_CORES}" == 1 ]] || cores=$((cores / 2))
  [[ "$cores" -ge 1 ]] || cores=1

  export MNFV_HOST_ARCHITECTURE="$host_arch"
  export MNFV_TARGET_ARCHITECTURE="$TARGET_ARCH"
  export MNFV_HOST_CORES="$cores"
  export MNFV_CROSS_COMPILATION="${CROSS_COMPILER_TOOLCHAIN%-}"
  export MNFV_CROSS_COMPILATION_DASH="${MNFV_CROSS_COMPILATION}-"
  export MNFV_MANIFEST_DIRECTORY="${project_dir}/ramfs/manifest"
  export MNFV_PROJECT_DIRECTORY="${project_dir}"
  export MNFV_INITFS_DIRECTORY="/initfs/${project_name}/${TARGET_ARCH}"

  root="/opt/cross/${MNFV_CROSS_COMPILATION}"
  if [[ "$host_arch" == "$TARGET_ARCH" ]]; then
    MNFV_CROSS_COMPILATION_DASH=""
    bindir="/usr/bin"
    tool_prefix=""
    export MNFV_INSTALL_PREFIX="/usr"
    export MNFV_CROSS_COMPILATION_CROSS_FILE=""
  else
    bindir="${root}/bin"
    tool_prefix="${MNFV_CROSS_COMPILATION_DASH}"
    export MNFV_INSTALL_PREFIX="${root}/usr"
    export MNFV_CROSS_COMPILATION_CROSS_FILE="${root}/${MNFV_CROSS_COMPILATION}-file"
  fi

  export MNFV_CROSS_COMPILATION_ABS_CC="${bindir}/${tool_prefix}gcc"
  export MNFV_CROSS_COMPILATION_ABS_CXX="${bindir}/${tool_prefix}g++"
  export MNFV_CROSS_COMPILATION_ABS_AR="${bindir}/${tool_prefix}ar"
  export MNFV_CROSS_COMPILATION_ABS_RANLIB="${bindir}/${tool_prefix}ranlib"
  export MNFV_CROSS_COMPILATION_ABS_OBJCOPY="${bindir}/${tool_prefix}objcopy"
  export MNFV_CROSS_COMPILATION_ABS_OBJDUMP="${bindir}/${tool_prefix}objdump"
  export MNFV_CROSS_COMPILATION_ABS_STRIP="${bindir}/${tool_prefix}strip"
  export MNFV_CROSS_COMPILATION_ABS_PKGCONFIG="${bindir}/${tool_prefix}pkg-config"
}

# envsubst only touches what's listed here, so shell variables that
# belong to the build scripts themselves (${CC}, ${HOME}, ...) stay as they are.
shell_format() {
  compgen -v MNFV_ | sed 's/.*/${&}/' | tr '\n' ' '
}

check_unresolved() {
  local bad
  bad="$(grep -oE '\$\{?MNFV_[A-Za-z0-9_]*\}?' <<<"$1" | sort -u | tr '\n' ' ')"
  [[ -z "$bad" ]] || error 1 "$2: unknown manifest variable(s): ${bad}"
}

# package variables must not leak from one entry into the next
clear_package_vars() {
  local v
  for v in $(compgen -v MNFV_PKG_) $(compgen -v MNFV_ENV_); do
    unset "$v"
  done
}

init_package_vars() {
  local entry="$1" id id_upper name directory patches_bool

  clear_package_vars

  id="$(jq -r '.id' <<<"$entry")"
  id_upper="${id^^}"
  id_upper="${id_upper//-/_}"
  name="$(jq -r '.name' <<<"$entry")"
  directory="$(jq -r '.directory' <<<"$entry")"
  patches_bool="$(jq -r '.patches' <<<"$entry")"

  export MNFV_PKG_ID="$id"
  export MNFV_PKG_ID_UPPER="$id_upper"
  export MNFV_PKG_NAME="$name"
  export MNFV_PKG_NAME_LOWER="${name,,}"
  export MNFV_PKG_NAME_UPPER="${name^^}"
  export MNFV_PKG_TYPE="$(jq -r '.type' <<<"$entry")"
  export MNFV_PKG_AUTHOR="$(jq -r '.author' <<<"$entry")"
  export MNFV_PKG_DESCRIPTION="$(jq -r '.description' <<<"$entry")"
  export MNFV_PKG_REPO_URL="$(jq -r '.repo.url' <<<"$entry")"
  export MNFV_PKG_REPO_BRANCH="$(jq -r '.repo.branch' <<<"$entry")"
  export MNFV_PKG_DIRECTORY="${PACKAGE_DIR}/${directory}"
  export MNFV_PKG_CONFIG_FILE_SCHEME="$(jq -r '.config_file_scheme' <<<"$entry")"
  export MNFV_PKG_OVERLAY_DIRECTORY="${project_dir}/ramfs/overlays/${id_upper}"

  if [[ "${patches_bool}" == "true" ]]; then
    export MNFV_PKG_PATCH_DIRECTORY="${project_dir}/patches/ramfs/${id_upper}"
  else
    export MNFV_PKG_PATCH_DIRECTORY=""
  fi
}

strip_empty_cross_file() {
  sed -e '/^ *--cross-file= *\\$/d' \
      -e 's/ *--cross-file= *\\$/ \\/' \
      -e 's/ *--cross-file=$//'
}

# expands every env value, in order, so a later one can use an earlier one.
# result (a json object) is left in REPLY
expand_env() {
  local entry="$1" key value
  REPLY="{}"

  for key in $(jq -r '.env | keys_unsorted[]' <<<"$entry"); do
    value="$(jq -r --arg k "$key" '.env[$k]' <<<"$entry" | envsubst "$(shell_format)")"
    check_unresolved "$value" "${MNFV_PKG_ID}: env.${key}"
    export "MNFV_ENV_${key}=${value}"
    REPLY="$(jq --arg k "$key" --arg v "$value" '. + {($k): $v}' <<<"$REPLY")"
  done
}

# $1 = entry, $2 = build_script | install_script. result (a json array) is left in REPLY
expand_script() {
  local entry="$1" key="$2" text

  if [[ "$(jq ".${key} | length" <<<"$entry")" -eq 0 ]]; then
    REPLY="[]"
    return
  fi

  text="$(jq -r ".${key}[]" <<<"$entry" | envsubst "$(shell_format)" | strip_empty_cross_file)"
  check_unresolved "$text" "${MNFV_PKG_ID}: ${key}"
  REPLY="$(jq -R . <<<"$text" | jq -s .)"
}

main() {
  local entry env_json build_json install_json
  local -a output_entries=()

  init_global_vars

  while IFS= read -r entry; do
    init_package_vars "$entry"

    expand_env "$entry"
    env_json="$REPLY"
    expand_script "$entry" build_script
    build_json="$REPLY"
    expand_script "$entry" install_script
    install_json="$REPLY"

    output_entries+=("$(jq -c \
      --arg patch_dir "$MNFV_PKG_PATCH_DIRECTORY" \
      --arg overlay_dir "$MNFV_PKG_OVERLAY_DIRECTORY" \
      --argjson env "$env_json" \
      --argjson build "$build_json" \
      --argjson install "$install_json" \
      '.overlay_directory = $overlay_dir | .env = $env | .build_script = $build | .install_script = $install' \
      <<<"$entry")")
  done < <(jq -c '.[]' "$MANIFEST_JSON")

  printf '%s\n' "${output_entries[@]}" | jq -s '.' > "$OUT_FILE"
  log "GEN" "$OUT_FILE"
}

main "$@"
