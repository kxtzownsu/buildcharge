#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}"/lib/common.sh

[[ $EUID -ne 0 ]] && error 1 "please run as root!"

SEARCH_PATTERN="${1:-buildcharge}"
MOUNTS=$(mount | grep "$SEARCH_PATTERN" | grep "/build-env/" | awk '{print $3}' | sort -r)

# We aren't mounted, we can safely exit.
[[ -z $MOUNTS ]] && exit 0

log "CLEANUP" "found $(echo "$MOUNTS" | wc -l)"

for MOUNT in $MOUNTS; do
  log "UNMOUNT" "$MOUNT"
  umount "$MOUNT"
done