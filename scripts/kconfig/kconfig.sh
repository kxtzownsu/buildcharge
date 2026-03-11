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
DOT_CONFIG="$PROJECT_DIR/.config"
KCONFIG_FILE="$PROJECT_DIR/build/Kconfig"
CMD="${1:-menuconfig}"

command -v menuconfig >/dev/null 2>&1 || python3 -c "import kconfiglib" >/dev/null 2>&1 || error 1 "kconfiglib is not installed"

kcmd() {
  local name="$1"
  shift

  if command -v "$name" >/dev/null 2>&1; then
    "$name" "$@"
  else
    python3 -m "kconfiglib.${name}" "$@" 2>/dev/null \
      || python3 "$(python3 -c "import kconfiglib, os; print(os.path.dirname(kconfiglib.__file__))")/../${name}.py" "$@"
  fi
}

[[ ! -f "$KCONFIG_FILE" ]] && {
  bash "$SCRIPT_DIR/gen-kconfig.sh" "$PROJECT_DIR/ramfs/manifest.json"
}

export KCONFIG_CONFIG="$DOT_CONFIG"

case "$CMD" in
  menuconfig|guiconfig)
    cd "$PROJECT_DIR"
    kcmd "$CMD" "$KCONFIG_FILE"
    bash "$SCRIPT_DIR/gen-config.sh"
    ;;

  check)
    cd "$PROJECT_DIR"
    if [[ ! -f "$DOT_CONFIG" ]]; then
      kcmd alldefconfig "$KCONFIG_FILE"
    else
      kcmd olddefconfig "$KCONFIG_FILE"
    fi
    bash "$SCRIPT_DIR/gen-config.sh"
    ;;

  olddefconfig)
    cd "$PROJECT_DIR"
    kcmd olddefconfig "$KCONFIG_FILE"
    bash "$SCRIPT_DIR/gen-config.sh"
    ;;

  gen-kconfig)
    bash "$SCRIPT_DIR/gen-kconfig.sh" "${2:-$PROJECT_DIR/ramfs/manifest.json}"
    ;;

  gen-config)
    bash "$SCRIPT_DIR/gen-config.sh"
    ;;

  *)
    error 1 "unknown command: $CMD"
    ;;
esac