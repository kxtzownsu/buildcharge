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
