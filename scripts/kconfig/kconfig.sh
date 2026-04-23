#!/bin/bash
set -e
project_name="buildcharge"

log() {
  local section="$1" message="$2"
  [[ ${#section} -gt 8 ]] && section="${section:0:5}..."
  while [[ ${#section} -lt 8 ]]; do section+=" "; done
  echo "  ${section^^}  ${message}"
}

error() { local code=$1; shift; log "ERROR" "$*"; exit "$code"; }

CMD="${1:-menuconfig}"; shift || true

KCONFIG_FILE="" DOT_CONFIG="" MANIFEST_FILE="" CONFIG_SH_OUT="" CONFIG_MK_OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kconfig)    KCONFIG_FILE="$2";  shift 2 ;;
    --dot-config) DOT_CONFIG="$2";    shift 2 ;;
    --manifest)   MANIFEST_FILE="$2"; shift 2 ;;
    --config-sh)  CONFIG_SH_OUT="$2"; shift 2 ;;
    --config-mk)  CONFIG_MK_OUT="$2"; shift 2 ;;
    *) error 1 "unknown argument: $1" ;;
  esac
done

command -v menuconfig >/dev/null 2>&1 \
  || python3 -c "import kconfiglib" >/dev/null 2>&1 \
  || error 1 "kconfiglib is not installed"

kcmd() {
  local name="$1"; shift
  if command -v "$name" >/dev/null 2>&1; then
    "$name" "$@"
  else
    python3 -m "kconfiglib.${name}" "$@" 2>/dev/null \
      || python3 "$(python3 -c "import kconfiglib,os; print(os.path.dirname(kconfiglib.__file__))")/../${name}.py" "$@"
  fi
}

gen_kconfig() {
  local manifest="$1" out="$2"
  [[ -f "$manifest" ]] || error 1 "manifest.json not found at $manifest"
  command -v jq >/dev/null 2>&1 || error 1 "jq is required to generate Kconfig"
  mkdir -p "$(dirname "$out")"

  {
cat <<EOF
# Automatically generated from gen_kconfig
# Do not edit directly.

mainmenu "${project_name} Configuration"

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
      local name author description repo_url repo_branch deps sym
      name="$(jq -r '.name'               <<<"$entry")"
      author="$(jq -r '.author'           <<<"$entry")"
      description="$(jq -r '.description' <<<"$entry")"
      repo_url="$(jq -r '.repo_url'       <<<"$entry")"
      repo_branch="$(jq -r '.repo_branch' <<<"$entry")"
      deps="$(jq -r '.dependencies[]?'    <<<"$entry")"

      sym="${name^^}"; sym="${sym//-/_}"

      echo "config PACKAGE_${sym}"
      echo "  bool \"${name}\""
      echo "  default y"

      [[ -n "$deps" ]] && while IFS= read -r dep; do
        echo "  depends on PACKAGE_$(echo "$dep" | tr '[:lower:]-' '[:upper:]_')"
      done <<<"$deps"

      local help_lines=()
      [[ -n "$description" && "$description" != "null" ]] && help_lines+=("$description")
      [[ -n "$author"      && "$author"      != "null" ]] && help_lines+=("Author: $author")
      [[ -n "$repo_url"    && "$repo_url"    != "null" ]] && help_lines+=("Source: $repo_url")
      [[ -n "$repo_branch" && "$repo_branch" != "null" ]] && help_lines+=("Branch: $repo_branch")

      if [[ ${#help_lines[@]} -gt 0 ]]; then
        echo "  help"
        for line in "${help_lines[@]}"; do echo "    $line"; done
      fi
      echo ""

      # config opts for this package
      local has_cfg
      has_cfg="$(jq -r 'has("config_options")' <<<"$entry")"

      if [[ "$has_cfg" == "true" ]]; then
        echo "if PACKAGE_${sym}"

        jq -c '.config_options | to_entries[]' <<<"$entry" | while read -r opt; do
          local opt_name opt_sym opt_desc opt_deps

          opt_name="$(jq -r '.key' <<<"$opt")"
          opt_sym="${opt_name^^}"
          opt_sym="${opt_sym//-/_}"

          opt_desc="$(jq -r '.value.description // ""' <<<"$opt")"
          opt_deps="$(jq -r '.value.dependencies[]?' <<<"$opt")"

          echo "config PACKAGE_${sym}_${opt_sym}"
          echo "  bool \"${opt_name}\""
          echo "  default n"
          echo "  depends on PACKAGE_${sym}"

          if [[ -n "$opt_deps" ]]; then
            while IFS= read -r dep; do
              [[ -z "$dep" ]] && continue
              dep_sym="$(echo "$dep" | tr '[:lower:]-' '[:upper:]_')"
              echo "  depends on PACKAGE_${dep_sym}"
            done <<<"$opt_deps"
          fi

          if [[ -n "$opt_desc" && "$opt_desc" != "null" ]]; then
            echo "  help"
            echo "    $opt_desc"
          fi

          echo ""
        done

        echo "endif"
      fi
    done < <(jq -c '.[]' "$manifest")

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
  } > "$out"

  log "GEN" "$out"
}

gen_config() {
  local dot_config="$1" config_sh_out="$2"
  [[ -f "$dot_config" ]] || error 1 ".config not found at $dot_config"
  mkdir -p "$(dirname "$config_sh_out")"

  {
    echo "# Auto-generated from .config, do not edit directly"
    echo "# Generated by kconfig.sh"
    echo ""
    while IFS= read -r line; do
      if [[ "$line" =~ ^#[[:space:]]CONFIG_([A-Za-z0-9_]+)[[:space:]]is[[:space:]]not[[:space:]]set ]]; then
        echo "CONFIG_${BASH_REMATCH[1]}=n"; continue
      fi
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// }"           ]] && continue
      [[ "$line" =~ ^CONFIG_[A-Za-z0-9_]+=.* ]] && echo "$line"
    done < "$dot_config"
  } > "$config_sh_out"

  log "GEN" "$config_sh_out"
}

gen_config_mk() {
  local dot_config="$1" config_mk_out="$2"
  [[ -f "$dot_config" ]] || error 1 ".config not found at $dot_config"
  mkdir -p "$(dirname "$config_mk_out")"

  {
    echo "# Auto-generated from .config, do not edit directly"
    echo "# Generated by kconfig.sh"
    echo ""
    while IFS= read -r line; do
      if [[ "$line" =~ ^#[[:space:]]CONFIG_([A-Za-z0-9_]+)[[:space:]]is[[:space:]]not[[:space:]]set ]]; then
        echo "CONFIG_${BASH_REMATCH[1]} := n"; continue
      fi
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// }"           ]] && continue
      if [[ "$line" =~ ^(CONFIG_[A-Za-z0-9_]+)=(.*)$ ]]; then
        local key="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
        [[ "$val" =~ ^\"(.*)\"$ ]] && val="${BASH_REMATCH[1]}"
        echo "${key} := ${val}"
      fi
    done < "$dot_config"
  } > "$config_mk_out"

  log "GEN" "$config_mk_out"
}

_gen_configs() {
  [[ -n "$CONFIG_SH_OUT" ]] && gen_config    "$DOT_CONFIG" "$CONFIG_SH_OUT"
  [[ -n "$CONFIG_MK_OUT" ]] && gen_config_mk "$DOT_CONFIG" "$CONFIG_MK_OUT"
}

require() {
  for var in "$@"; do
    if [[ -z "${!var}" ]]; then
      local flag
      case "$var" in
        KCONFIG_FILE)  flag="--kconfig" ;;
        DOT_CONFIG)    flag="--dot-config" ;;
        MANIFEST_FILE) flag="--manifest" ;;
        CONFIG_SH_OUT) flag="--config-sh" ;;
        CONFIG_MK_OUT) flag="--config-mk" ;;
        *)             flag="--${var,,}" ;;
      esac
      error 1 "$var is required for this command (pass $flag)"
    fi
  done
}

export KCONFIG_CONFIG="$DOT_CONFIG"

case "$CMD" in
  menuconfig|guiconfig)
    require KCONFIG_FILE DOT_CONFIG CONFIG_SH_OUT
    [[ -f "$KCONFIG_FILE" ]] || { require MANIFEST_FILE; gen_kconfig "$MANIFEST_FILE" "$KCONFIG_FILE"; }
    kcmd "$CMD" "$KCONFIG_FILE"
    _gen_configs
    ;;

  check)
    require KCONFIG_FILE DOT_CONFIG CONFIG_SH_OUT
    [[ -f "$KCONFIG_FILE" ]] || { require MANIFEST_FILE; gen_kconfig "$MANIFEST_FILE" "$KCONFIG_FILE"; }
    if [[ ! -f "$DOT_CONFIG" ]]; then
      kcmd alldefconfig "$KCONFIG_FILE"
    else
      kcmd olddefconfig "$KCONFIG_FILE"
    fi
    _gen_configs
    ;;

  olddefconfig)
    require KCONFIG_FILE DOT_CONFIG CONFIG_SH_OUT
    kcmd olddefconfig "$KCONFIG_FILE"
    _gen_configs
    ;;

  gen-kconfig)
    require MANIFEST_FILE KCONFIG_FILE
    gen_kconfig "$MANIFEST_FILE" "$KCONFIG_FILE"
    ;;

  gen-config)
    require DOT_CONFIG
    [[ -n "$CONFIG_SH_OUT" || -n "$CONFIG_MK_OUT" ]] \
      || error 1 "at least one of CONFIG_SH_OUT or CONFIG_MK_OUT must be provided"
    _gen_configs
    ;;

  *)
    error 1 "unknown command: $CMD"
    ;;
esac