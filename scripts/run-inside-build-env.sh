#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}"/lib/common.sh


ENV_DIR="$1"
PROJECT_DIR="$2"
CMD_TO_RUN="$3"

[[ $EUID -ne 0 ]] && error 1 "please run as root!"
[[ -z "$PROJECT_DIR" ]] && error 1 "missing build dir!" 
[[ -z "$CMD_TO_RUN" ]] && error 1 "missing command to run!"


## we're running as root past this, be careful! ##

mountpoints=(
	/dev
	/dev/pts
	/sys
	/proc
	/run
)

for mountpoint in "${mountpoints[@]}"; do
  mount --bind "${mountpoint}" "${ENV_DIR}/${mountpoint}" 2>/dev/null
done

mkdir -p "${ENV_DIR}/buildcharge"
mount --bind "${PROJECT_DIR}" "${ENV_DIR}/buildcharge"

cat <<EOF > "${ENV_DIR}/tmp/command_to_run"
#!/bin/bash
# yes bashrc handles this, but you can't be too safe!
source /etc/profile 2>/dev/null || true
source ~/.profile 2>/dev/null || true
source /etc/bash/bashrc 2>/dev/null || true
source /etc/bash/bash_completion.sh 2>/dev/null || true

# make sure we're running in the project dir
cd /buildcharge

${CMD_TO_RUN}
EOF

chmod +x "${ENV_DIR}/tmp/command_to_run"

chroot "${ENV_DIR}" "/tmp/command_to_run"
EXIT_CODE=$?

## cleanup ##
rm -rf "${ENV_DIR}/tmp/command_to_run"
umount "${ENV_DIR}/buildcharge" 2>/dev/null || true

for ((i=${#mountpoints[@]}-1; i>=0; i--)); do
  umount "${ENV_DIR}/${mountpoints[i]}" 2>/dev/null || true
done

exit $EXIT_CODE
