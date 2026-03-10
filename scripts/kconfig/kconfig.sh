#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# TODO(kxtz): don't hardcode PROJECT_DIR, it should be passed to us, otherwise assume it's `.`
PROJECT_DIR="$(realpath "$SCRIPT_DIR/../..")"
DOT_CONFIG="$PROJECT_DIR/.config"
KCONFIG_FILE="$PROJECT_DIR/build/Kconfig"
CMD="${1:-menuconfig}"

command -v menuconfig >/dev/null 2>&1 || python3 -c "import kconfiglib" >/dev/null 2>&1 || error 1 "kconfiglib is not installed."

kcmd(){
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
  log "gen" "Kconfig"
  bash "$SCRIPT_DIR/gen-kconfig.sh"
}

export KCONFIG_CONFIG="$DOT_CONFIG"

case "$CMD" in
  menuconfig)
    cd "$PROJECT_DIR"
    kcmd menuconfig "$KCONFIG_FILE"
    bash "$SCRIPT_DIR/gen-config.sh"
    ;;

  guiconfig)
    cd "$PROJECT_DIR"
    kcmd guiconfig "$KCONFIG_FILE"
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
    bash "$SCRIPT_DIR/gen-kconfig.sh" "$MANIFEST_FILE"
    ;;

  gen-config)
    bash "$SCRIPT_DIR/gen-config.sh"
    ;;

  *)
    error 1 "Unknown command: $CMD (expected menuconfig|guiconfig|check|olddefconfig|gen-kconfig|gen-config)"
    ;;
esac