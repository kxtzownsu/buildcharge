#!/bin/bash
set -e

log() {
  local section="$1"
  local message="$2"
  [[ ${#section} -gt 8 ]] && section="${section:0:5}..."
  while [[ ${#section} -lt 8 ]]; do section="${section} "; done
  section=$(echo "$section" | tr '[:lower:]' '[:upper:]')
  echo "  ${section}  ${message}"
}

error() {
  local code=$1
  shift
  log "ERROR" "$@"
  exit $code
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(realpath "$SCRIPT_DIR/../..")"
MANIFEST_FILE="$1"
OUTPUT_KCONFIG="$PROJECT_DIR/build/Kconfig"

[[ ! -f "$MANIFEST_FILE" ]] && error 1 "manifest.json not found at $MANIFEST_FILE"
command -v jq >/dev/null 2>&1 || error 1 "jq is required to generate Kconfig"

mkdir -p "$(dirname "$OUTPUT_KCONFIG")"

{
cat <<'EOF'
# Automatically generated from ramfs/manifest.json
# Do not edit directly.

mainmenu "buildcharge Configuration"

choice
  prompt "Target architecture"
  default ARCH_SELECTION_X86_64

config ARCH_SELECTION_X86_64
  bool "x86_64"

config ARCH_SELECTION_AARCH64
  bool "aarch64 (arm64)"

endchoice

config ARCH_SELECTION
  string
  default "x86_64"   if ARCH_SELECTION_X86_64
  default "aarch64"  if ARCH_SELECTION_AARCH64

menu "Packages"

config PACKAGES
  bool "Enable package building"
  default y
  help
    Master switch for the package build stage. Disable to skip
    all package compilation (e.g. for a kernel-only build).

if PACKAGES
EOF

while IFS= read -r entry; do
    name="$(jq -r '.name' <<<"$entry")"
    author="$(jq -r '.author' <<<"$entry")"
    description="$(jq -r '.description' <<<"$entry")"
    repo_url="$(jq -r '.repo_url' <<<"$entry")"
    repo_branch="$(jq -r '.repo_branch' <<<"$entry")"
    deps="$(jq -r '.dependencies[]?' <<<"$entry")"

    name_upper="${name^^}"
    sym="${name_upper//-/_}"

    echo "config PACKAGE_${sym}"
    echo "  bool \"${name}\""
    echo "  default y"

    [[ -n "$deps" ]] && for dep in $deps; do
        dep_sym="$(echo "$dep" | tr '[:lower:]-' '[:upper:]_')"
        echo "  depends on PACKAGE_${dep_sym}"
    done

    help_lines=()
    [[ -n "$description" && "$description" != "null" ]] && help_lines+=("$description")
    [[ -n "$author" && "$author" != "null" ]] && help_lines+=("Author: $author")
    [[ -n "$repo_url" && "$repo_url" != "null" ]] && help_lines+=("Source: $repo_url")
    [[ -n "$repo_branch" && "$repo_branch" != "null" ]] && help_lines+=("Branch: $repo_branch")

    if [[ ${#help_lines[@]} -gt 0 ]]; then
        echo "  help"
        for line in "${help_lines[@]}"; do
            echo "    $line"
        done
    fi
    echo ""
done < <(jq -c '.[]' "$MANIFEST_FILE")

echo "endif"
echo "endmenu"

cat <<'EOF'
menu "Kernel"

config KERNEL
  bool "Enable kernel compilation"
  default y
  help
    Master switch for the kernel build stage. Disable to skip
    kernel compilation (e.g: for a ramfs-only build).

config KERNEL_RAMFS_BUNDLED
  bool "Bundle ramfs inside kernel"
  default y
  depends on KERNEL
  help
    Bundle the ramfs inside of the kernel, required for depthcharge.
    Use this only when testing ramfs changes in QEMU when there isn't any
    kernel changes.

endmenu
EOF

} > "$OUTPUT_KCONFIG"

log "GEN" "$OUTPUT_KCONFIG"