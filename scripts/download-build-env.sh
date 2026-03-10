#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}"/lib/common.sh

REPO_URL="https://github.com/kxtzownsu/build-env"
ENV_OS="Alpine"

ENV_DIR="$1"
ENV_ARCH="$2"
VERBOSE="$3"

[[ -z "$ENV_DIR" ]] && error 1 "missing build-env dir!"
[[ -z "$ENV_ARCH" ]] && error 1 "missing architecture!"

log "WGET" "${ENV_OS}.tgz"
# this is github-specific & build-env specific especially with the release names
wget -q --show-progress -O "${ENV_DIR}/os.tgz" "${REPO_URL}/releases/download/${ENV_OS,,}-${ENV_ARCH}-latest/${ENV_OS}.tgz"

log "EXTRACT" "${ENV_OS}.tgz"
if [ "$VERBOSE" == "1" ]; then
  tar -xzf "${ENV_DIR}/os.tgz" -C "${ENV_DIR}"
else
  tar -xzf "${ENV_DIR}/os.tgz" -C "${ENV_DIR}" 2>/dev/null
fi

rm -f "${ENV_DIR}/os.tgz"
