#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}"/lib/common.sh

ENV_DIR="$1"
PROJECT_DIR="$2"
TARGET="$3"
VERBOSE="$4"

[[ $EUID -ne 0 ]] && error 1 "please run $0 as root!"
[[ -z "$ENV_DIR" ]] && error 1 "missing build-env dir!"
[[ -z "$PROJECT_DIR" ]] && error 1 "missing project dir!"
[[ -z "$TARGET" ]] && error 1 "missing target!"

## we're running as root past this, be careful! ##

# TODO(kxtz): find a better way to track the mounted state
MOUNTED=0

mountpoints=(
	/dev
	/dev/pts
	/sys
	/proc
	/run
)

cleanup() {
  if [ "$MOUNTED" -eq 1 ]; then
    log "CLEANUP"   "unmounting build-env"
    umount "${ENV_DIR}/buildcharge" 2>/dev/null || umount -l "${ENV_DIR}/buildcharge" 2>/dev/null || true
    
    for ((i=${#mountpoints[@]}-1; i>=0; i--)); do
      umount "${ENV_DIR}/${mountpoints[i]}" 2>/dev/null || umount -l "${ENV_DIR}/${mountpoints[i]}" 2>/dev/null || true
    done
    
    MOUNTED=0
  fi
}

# we should ALWAYS cleanup.
trap cleanup EXIT INT TERM

for mountpoint in "${mountpoints[@]}"; do
	mount --bind $mountpoint "${ENV_DIR}/${mountpoint}" 2>/dev/null || true
done

# this is quicker than copying it but it's dangerous
# because if we accidentally nuke the folder, our
# progress is gone.
mkdir -p "${ENV_DIR}/buildcharge"
mount --bind "$PROJECT_DIR" "${ENV_DIR}/buildcharge"

MOUNTED=1

cat <<EOF > "${ENV_DIR}/tmp/build_command"
#!/bin/bash
source /etc/profile 2>/dev/null || true
source ~/.profile 2>/dev/null || true
source /etc/bash/bashrc 2>/dev/null || true
source /etc/bash/bash_completion.sh 2>/dev/null || true

cd /buildcharge
make --no-print-directory internal_buildenv TARGET=${TARGET} VERBOSE=${VERBOSE} BUILDENV=1
EOF

chmod +x "${ENV_DIR}/tmp/build_command"

# so we visually know when we're entering/exiting build-env
echo "----| Entering build-env |----"
chroot "${ENV_DIR}" "/tmp/build_command"
EXIT_CODE=$?

echo "----| Exiting build-env ($EXIT_CODE) |----"

rm -f "${ENV_DIR}/tmp/build_command"

# exit so cleanup() gets called
exit $EXIT_CODE