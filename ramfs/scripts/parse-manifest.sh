#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}"/lib/common.sh

MANIFEST_JSON="$1"
CROSS_COMPILER_TOOLCHAIN="$2"
TARGET_ARCH="$3"

require_arg "$MANIFEST_JSON" "manifest json"
require_arg "$CROSS_COMPILER_TOOLCHAIN" "cross compiler toolchain"
require_arg "$TARGET_ARCH" "target arch"

MANIFEST_JSON="$(realpath "$MANIFEST_JSON")"
MANIFEST_DIRECTORY="${4:-$(dirname "$MANIFEST_JSON")}"

command -v jq >/dev/null 2>&1 || error 1 "jq is required"
[[ ! -f "$MANIFEST_JSON" ]] && error 1 "manifest not found: $MANIFEST_JSON"

MANIFEST_VAR_HOST_ARCHITECTURE="$(uname -m)"
MANIFEST_VAR_CROSS_COMPILATION="${CROSS_COMPILER_TOOLCHAIN%-}"
MANIFEST_VAR_CROSS_COMPILATION_DASH="${MANIFEST_VAR_CROSS_COMPILATION}-"
MANIFEST_VAR_TARGET_ARCHITECTURE="$TARGET_ARCH"
MANIFEST_VAR_MANIFEST_DIRECTORY="$MANIFEST_DIRECTORY"
MANIFEST_VAR_PROJECT_DIRECTORY="/${project_name}"

case "$TARGET_ARCH" in
  x86_64|aarch64) ;;
  *) error 1 "unsupported arch: $TARGET_ARCH" ;;
esac

if [[ "${MANIFEST_VAR_HOST_ARCHITECTURE}" == "${MANIFEST_VAR_TARGET_ARCHITECTURE}" ]]; then
  MANIFEST_VAR_CROSS_COMPILATION_DASH=""
  MANIFEST_VAR_INSTALL_PREFIX="/usr"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_CC="/usr/bin/gcc"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_CXX="/usr/bin/g++"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_AR="/usr/bin/ar"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_RANLIB="/usr/bin/ranlib"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_OBJCOPY="/usr/bin/objcopy"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_OBJDUMP="/usr/bin/objdump"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_STRIP="/usr/bin/strip"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_PKGCONFIG="/usr/bin/pkg-config"
  MANIFEST_VAR_CROSS_COMPILATION_CROSS_FILE=""
else
  MANIFEST_VAR_INSTALL_PREFIX="/opt/cross/${MANIFEST_VAR_CROSS_COMPILATION}/usr"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_CC="/opt/cross/${MANIFEST_VAR_CROSS_COMPILATION}/bin/${MANIFEST_VAR_CROSS_COMPILATION_DASH}gcc"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_CXX="/opt/cross/${MANIFEST_VAR_CROSS_COMPILATION}/bin/${MANIFEST_VAR_CROSS_COMPILATION_DASH}g++"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_AR="/opt/cross/${MANIFEST_VAR_CROSS_COMPILATION}/bin/${MANIFEST_VAR_CROSS_COMPILATION_DASH}ar"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_RANLIB="/opt/cross/${MANIFEST_VAR_CROSS_COMPILATION}/bin/${MANIFEST_VAR_CROSS_COMPILATION_DASH}ranlib"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_OBJCOPY="/opt/cross/${MANIFEST_VAR_CROSS_COMPILATION}/bin/${MANIFEST_VAR_CROSS_COMPILATION_DASH}objcopy"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_OBJDUMP="/opt/cross/${MANIFEST_VAR_CROSS_COMPILATION}/bin/${MANIFEST_VAR_CROSS_COMPILATION_DASH}objdump"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_STRIP="/opt/cross/${MANIFEST_VAR_CROSS_COMPILATION}/bin/${MANIFEST_VAR_CROSS_COMPILATION_DASH}strip"
  MANIFEST_VAR_CROSS_COMPILATION_ABS_PKGCONFIG="/opt/cross/${MANIFEST_VAR_CROSS_COMPILATION}/bin/${MANIFEST_VAR_CROSS_COMPILATION_DASH}pkg-config"
  MANIFEST_VAR_CROSS_COMPILATION_CROSS_FILE="/opt/cross/${MANIFEST_VAR_CROSS_COMPILATION}/${MANIFEST_VAR_CROSS_COMPILATION}-file"
fi

init_manifest_vars() {
  local entry="$1"
  MANIFEST_VAR_PACKAGE_NAME="$(jq -r .name <<<"$entry")"
  MANIFEST_VAR_PACKAGE_NAME_LOWER="$(echo "$MANIFEST_VAR_PACKAGE_NAME" | tr 'A-Z' 'a-z')"
  MANIFEST_VAR_PACKAGE_NAME_UPPER="$(echo "$MANIFEST_VAR_PACKAGE_NAME" | tr 'a-z' 'A-Z')"
  MANIFEST_VAR_PACKAGE_AUTHOR="$(jq -r .author <<<"$entry")"
  MANIFEST_VAR_PACKAGE_DESCRIPTION="$(jq -r .description <<<"$entry")"
  MANIFEST_VAR_PACKAGE_REPO_URL="$(jq -r .repo_url <<<"$entry")"
  MANIFEST_VAR_PACKAGE_REPO_BRANCH="$(jq -r .repo_branch <<<"$entry")"
  MANIFEST_VAR_PACKAGE_DIRECTORY="$(jq -r .directory <<<"$entry")"
  MANIFEST_VAR_PACKAGE_PATCH_DIRECTORY="$(jq -r .patch_directory <<<"$entry")"
  MANIFEST_VAR_PACKAGE_CONFIG_FILE="$(jq -r '.config_file // false' <<<"$entry")"
  MANIFEST_VAR_PACKAGE_OVERLAY_DIRECTORY="$(jq -r .overlay_directory <<<"$entry")"
}

expand_manifest_vars() {
  local s="$1"
  
  # export so envsubst sees them...
  export MANIFEST_VAR_CROSS_COMPILATION_ABS_PKGCONFIG
  export MANIFEST_VAR_CROSS_COMPILATION_ABS_OBJCOPY
  export MANIFEST_VAR_CROSS_COMPILATION_ABS_OBJDUMP
  export MANIFEST_VAR_CROSS_COMPILATION_ABS_RANLIB
  export MANIFEST_VAR_CROSS_COMPILATION_ABS_STRIP
  export MANIFEST_VAR_CROSS_COMPILATION_ABS_CXX
  export MANIFEST_VAR_CROSS_COMPILATION_ABS_AR
  export MANIFEST_VAR_CROSS_COMPILATION_ABS_CC
  export MANIFEST_VAR_CROSS_COMPILATION_CROSS_FILE
  export MANIFEST_VAR_CROSS_COMPILATION_DASH
  export MANIFEST_VAR_CROSS_COMPILATION
  export MANIFEST_VAR_TARGET_ARCHITECTURE
  export MANIFEST_VAR_HOST_ARCHITECTURE
  export MANIFEST_VAR_INSTALL_PREFIX
  export MANIFEST_VAR_MANIFEST_DIRECTORY
  export MANIFEST_VAR_PROJECT_DIRECTORY
  export MANIFEST_VAR_PACKAGE_PATCH_DIRECTORY
  export MANIFEST_VAR_PACKAGE_CONFIG_FILE
  export MANIFEST_VAR_PACKAGE_REPO_BRANCH
  export MANIFEST_VAR_PACKAGE_REPO_URL
  export MANIFEST_VAR_PACKAGE_DESCRIPTION
  export MANIFEST_VAR_PACKAGE_DIRECTORY
  export MANIFEST_VAR_PACKAGE_NAME_LOWER
  export MANIFEST_VAR_PACKAGE_NAME_UPPER
  export MANIFEST_VAR_PACKAGE_NAME
  export MANIFEST_VAR_PACKAGE_AUTHOR
  export MANIFEST_VAR_PACKAGE_OVERLAY_DIRECTORY
  
  printf '%s' "$s" | envsubst
}

strip_empty_cross_file() {
  local s="$1"
  s="$(echo "$s" | sed 's/ *--cross-file= *\\$//g')"
  s="$(echo "$s" | sed 's/ *--cross-file= *//g')"
  printf '%s' "$s"
}

main() {
  local output_entries=()

  while IFS= read -r entry; do
    init_manifest_vars "$entry"

    local expanded_patch_dir expanded_overlay_dir expanded_build_cmd_json expanded_entry
    expanded_patch_dir="$(expand_manifest_vars "$MANIFEST_VAR_PACKAGE_PATCH_DIRECTORY")"
    expanded_overlay_dir="$(expand_manifest_vars "$MANIFEST_VAR_PACKAGE_OVERLAY_DIRECTORY")"
    expanded_build_cmd_json="$(
      while IFS= read -r line; do 
        expand_manifest_vars "$line"
        echo
      done < <(jq -r 'if (.build_cmd | type) == "array" then .build_cmd[] else .build_cmd end' <<<"$entry") |
      sed '/^ *--cross-file= *\\$/d' |
      sed 's/ *--cross-file= *\\$/ \\/' |
      sed 's/ *--cross-file=$//' |
      jq -R . | jq -s .
    )"
    expanded_entry="$(jq \
      --arg patch_dir "$expanded_patch_dir" \
      --arg overlay_dir "$expanded_overlay_dir" \
      --argjson build_cmd "$expanded_build_cmd_json" \
      '.patch_directory = $patch_dir | .overlay_directory = $overlay_dir | .build_cmd = $build_cmd' \
      <<<"$entry")"

    output_entries+=("$expanded_entry")
  done < <(jq -c '.[]' "$MANIFEST_JSON")

  local out="/tmp/manifest.json"
  printf '%s\n' "${output_entries[@]}" | jq -s '.' > "$out"
  log "GEN" "$out"
}

main "$@"
