project_name="buildcharge"

log(){
  section="$1"
  message="$2"

  # section is more than 8 chars, truncate it.
  if [[ ${#section} -gt 8 ]]; then
    section="${section:0:5}..."
  fi

  # section is less than 8 chars, append spaces to it.
  while [[ ${#section} -lt 8 ]]; do
    section="${section} "
  done

  # make sure section is uppercase
  section=$(echo "$section" | tr '[:lower:]' '[:upper:]')

  echo "  ${section}  ${message}"
}

error(){
  code=$1
  shift
  log "ERROR" "$@"
  exit $code
}

require_root(){
  [[ $EUID -ne 0 ]] && error 1 "please run as root!"
}

require_arg(){
  local arg_value="$1"
  local arg_name="$2"
  [[ -z "$arg_value" ]] && error 1 "missing ${arg_name}!"
}

BUILD_ENV_MOUNTPOINTS=(
  /dev
  /dev/pts
  /sys
  /proc
  /run
)

mount_build_env(){
  local env_dir="$1"
  local project_dir="$2"

  require_arg "$env_dir" "env_dir"

  for mountpoint in "${BUILD_ENV_MOUNTPOINTS[@]}"; do
    mount --bind "$mountpoint" "${env_dir}/${mountpoint}" 2>/dev/null || true
  done

  if [[ -n "$project_dir" ]]; then
    mkdir -p "${env_dir}/${project_name}"
    mount --bind "$project_dir" "${env_dir}/${project_name}"
  fi
}

unmount_build_env(){
  local env_dir="$1"

  require_arg "$env_dir" "env_dir"

  umount "${env_dir}/${project_name}" 2>/dev/null || umount -l "${env_dir}/${project_name}" 2>/dev/null || true

  for ((i=${#BUILD_ENV_MOUNTPOINTS[@]}-1; i>=0; i--)); do
    umount "${env_dir}/${BUILD_ENV_MOUNTPOINTS[i]}" 2>/dev/null || umount -l "${env_dir}/${BUILD_ENV_MOUNTPOINTS[i]}" 2>/dev/null || true
  done
}

create_chroot_command(){
  local env_dir="$1"
  local command_content="$2"
  local command_file="${env_dir}/tmp/build_command"

  require_arg "$env_dir" "env_dir"
  require_arg "$command_content" "command_content"

  cat <<EOF > "$command_file"
#!/bin/bash
source /etc/profile 2>/dev/null || true
source ~/.profile 2>/dev/null || true
source /etc/bash/bashrc 2>/dev/null || true
source /etc/bash/bash_completion.sh 2>/dev/null || true

cd /${project_name}

$command_content
EOF

  chmod +x "$command_file"
  echo "$command_file"
}

exec_in_chroot(){
  local env_dir="$1"
  local command_file="$2"

  require_arg "$env_dir" "env_dir"
  require_arg "$command_file" "command_file"

  echo "----| Entering build-env |----"
  chroot "$env_dir" "$command_file"
  local exit_code=$?
  echo "----| Exiting build-env (${exit_code}) |----"

  rm -f "$command_file"

  return $exit_code
}

run_in_build_env(){
  local env_dir="$1"
  local project_dir="$2"
  local command_content="$3"

  require_arg "$env_dir" "env_dir"
  require_arg "$command_content" "command_content"

  local _mounted=0

  _run_in_build_env_cleanup() {
    if [[ "$_mounted" -eq 1 ]]; then
      log "CLEANUP" "unmounting build-env"
      unmount_build_env "$env_dir"
      _mounted=0
    fi
  }

  trap _run_in_build_env_cleanup EXIT INT TERM

  mount_build_env "$env_dir" "$project_dir"
  _mounted=1

  local command_file
  command_file=$(create_chroot_command "$env_dir" "$command_content")

  exec_in_chroot "$env_dir" "$command_file"

  exit $?
}