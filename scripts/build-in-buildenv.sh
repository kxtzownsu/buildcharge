#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}"/lib/common.sh
[[ "$VERBOSE" == 1 ]] && set -x

ENV_DIR="$1"
PROJECT_DIR="$2"
TARGET="$3"

require_root
require_arg "$ENV_DIR" "build-env dir"
require_arg "$PROJECT_DIR" "project dir"
require_arg "$TARGET" "target"

COMMAND_CONTENT="make --no-print-directory internal_buildenv TARGET=${TARGET} VERBOSE=${VERBOSE} BUILDENV=1"

run_in_build_env "$ENV_DIR" "$PROJECT_DIR" "$COMMAND_CONTENT"