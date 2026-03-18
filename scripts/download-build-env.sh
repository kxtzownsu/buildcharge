#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}"/lib/common.sh
[[ "$VERBOSE" == 1 ]] && set -x

REPO_URL="https://github.com/kxtzownsu/build-env"
ENV_OS="Alpine"

ENV_DIR="$1"
ENV_ARCH="$2"

require_arg "$ENV_DIR" "build-env dir"
require_arg "$ENV_ARCH" "architecture"

[[ ! -d "$ENV_DIR" ]] && mkdir -p "$ENV_DIR"

DOWNLOAD_URL="${REPO_URL}/releases/download/${ENV_OS,,}-${ENV_ARCH}-latest/${ENV_OS}.tgz"
TARBALL="${ENV_DIR}/os.tgz"

log "WGET" "${ENV_OS}.tgz"
wget -q --show-progress -O "$TARBALL" "$DOWNLOAD_URL" || error 1 "failed to download build environment"

log "EXTRACT" "${ENV_OS}.tgz"
if [[ "$VERBOSE" == "1" ]]; then
  tar -xzf "$TARBALL" -C "$ENV_DIR" || error 1 "failed to extract tarball"
else
  tar -xzf "$TARBALL" -C "$ENV_DIR" 2>/dev/null || error 1 "failed to extract tarball"
fi

rm -f "$TARBALL"