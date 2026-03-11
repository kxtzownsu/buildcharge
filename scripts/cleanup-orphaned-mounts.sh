#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}"/lib/common.sh

require_root

SEARCH_PATTERN="${1:-buildcharge}"
MOUNTS=$(mount | grep "$SEARCH_PATTERN" | grep "/build-env/" | awk '{print $3}' | sort -r)

[[ -z "$MOUNTS" ]] && exit 0

MOUNT_COUNT=$(echo "$MOUNTS" | wc -l)
log "CLEANUP" "found ${MOUNT_COUNT} mount(s)"

FAILED=0
for MOUNT in $MOUNTS; do
  log "UNMOUNT" "$MOUNT"
  if ! umount "$MOUNT" 2>/dev/null; then
    log "WARNING" "lazy unmount for $MOUNT"
    umount -l "$MOUNT" 2>/dev/null || ((FAILED++))
  fi
done

[[ $FAILED -gt 0 ]] && error 1 "failed to unmount ${FAILED} mount point(s)"
exit 0