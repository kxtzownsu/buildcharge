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