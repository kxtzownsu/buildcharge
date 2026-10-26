#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}"/lib/common.sh
[[ "${VERBOSE}" == 1 ]] && set -x

# usage: preprocess-manifest.sh <manifest.json.pre> <output manifest.json> [target arch]
PRE_FILE="$1"
OUT_FILE="$2"
TARGET_ARCH="$3"

MAX_INCLUDE_DEPTH=16

require_arg "${PRE_FILE}" "manifest.json.pre"
require_arg "${OUT_FILE}" "output manifest"
command -v jq >/dev/null 2>&1 || error 1 "jq is required"
[[ -f "${PRE_FILE}" ]] || error 1 "manifest not found: ${PRE_FILE}"

PRE_FILE="$(realpath "${PRE_FILE}")"
MANIFEST_DIR="$(dirname "${PRE_FILE}")"

# the only variables that exist while includes are being resolved,
# anything else is an error instead of silently turning into nothing.
declare -A INCLUDE_VARS=(
  [MANIFEST_DIR]="${MANIFEST_DIR}"
  [MNFV_MANIFEST_DIRECTORY]="${MANIFEST_DIR}"
  [MNFV_HOST_ARCHITECTURE]="$(uname -m)"
)
[[ -n "${TARGET_ARCH}" ]] && INCLUDE_VARS[MNFV_TARGET_ARCHITECTURE]="${TARGET_ARCH}"

VAR_RE='\$\{([A-Za-z_][A-Za-z0-9_]*)\}'
INCLUDE_RE='^[[:space:]]*#include[[:space:]]+"([^"]+)"[[:space:]]*;?[[:space:]]*$'

# every function below hands its result back through REPLY, not stdout,
# so error() can still print from inside them.

expand_include_vars() {
  local input="$1" rest="$1" out="" name
  while [[ "${rest}" =~ ${VAR_RE} ]]; do
    name="${BASH_REMATCH[1]}"
    [[ -n "${INCLUDE_VARS[${name}]+set}" ]] \
      || error 1 "unknown variable \${${name}} in include path '${input}'"
    out+="${rest%%"${BASH_REMATCH[0]}"*}${INCLUDE_VARS[${name}]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
  REPLY="${out}${rest}"
}

# $1 = raw path, $2 = directory of the file that contains it (${MNFV_CWD})
resolve_include_path() {
  local path
  INCLUDE_VARS[MNFV_CWD]="$2"
  expand_include_vars "$1"
  path="${REPLY}"
  [[ "${path}" == /* ]] || path="$2/${path}"
  [[ -f "${path}" ]] || error 1 "include not found: ${path} (from '$1')"
  REPLY="$(realpath "${path}")"
}

# removes /* ... */ comments but keeps the newlines so line numbers still match
strip_comments() {
  local rest="$1" out="" comment
  while [[ "${rest}" == *'/*'* ]]; do
    out+="${rest%%/\**}"
    rest="${rest#*/\*}"
    [[ "${rest}" == *'*/'* ]] || error 1 "${PRE_FILE}: unterminated /* comment"
    comment="${rest%%\*/*}"
    out+="${comment//[!$'\n']/}"
    rest="${rest#*\*/}"
  done
  REPLY="${out}${rest}"
}

# appends every entry found in $1 to ENTRIES_FILE, one compact json object per line.
# an object with an "_include" key is replaced by whatever it points to.
resolve_file() {
  local file="$1" depth="$2" stack="$3"
  local dir json_err kind paths_out node p
  local -a nodes paths

  (( depth > MAX_INCLUDE_DEPTH )) && error 1 "includes nested more than ${MAX_INCLUDE_DEPTH} deep: ${file}"
  case ":${stack}:" in
    *":${file}:"*) error 1 "include cycle: ${file}" ;;
  esac
  stack="${stack}:${file}"
  dir="$(dirname "${file}")"

  json_err="$(jq empty "${file}" 2>&1)" || error 1 "${file}: ${json_err}"

  local nodes_file
  nodes_file="$(mktemp)"
  jq -c 'if type == "array" then .[] else . end' "${file}" > "${nodes_file}" || {
    rm -f "${nodes_file}"
    error 1 "${file}: failed to read entries"
  }

  while IFS= read -r node || [[ -n "${node}" ]]; do
    [[ -z "${node}" ]] && continue
    kind="$(jq -r 'if type != "object" then "invalid" elif has("_include") then "include" else "entry" end' <<<"${node}")"
    case "${kind}" in
      invalid)
        rm -f "${nodes_file}"
        error 1 "${file}: every entry must be a json object"
        ;;
      entry)
        printf '%s\n' "${node}" >> "${ENTRIES_FILE}"
        ;;
      include)
        jq -e '(keys - ["_include", "//"]) | length == 0' <<<"${node}" >/dev/null \
          || { rm -f "${nodes_file}"; error 1 "${file}: '_include' can't be mixed with other keys (only '//' comments)"; }

        paths_out="$(jq -r '._include
          | if type == "string" and length > 0 then .
            elif type == "array" and all(.[]; type == "string" and length > 0) then .[]
            else error("bad _include") end' <<<"${node}" 2>/dev/null)" \
          || { rm -f "${nodes_file}"; error 1 "${file}: '_include' must be a path or an array of paths"; }

        paths=()
        [[ -n "${paths_out}" ]] && mapfile -t paths <<<"${paths_out}"
        for p in "${paths[@]}"; do
          resolve_include_path "${p}" "${dir}"
          resolve_file "${REPLY}" $((depth + 1)) "${stack}"
        done
        ;;
    esac
  done < "${nodes_file}"
  rm -f "${nodes_file}"
}

read -r -d '' VALIDATE_JQ <<'EOF'
def nonempty: type == "string" and length > 0;
def strs: type == "array" and all(.[]; type == "string");
def known: ["name", "id", "type", "author", "description", "dependencies", "repo", "directory",
            "patches", "config_file_scheme", "config_options", "env",
            "build_script", "install_script"];

. as $all
| (reduce range(0; length) as $i ({};
    if ($all[$i].id | type) == "string" and .[$all[$i].id] == null then .[$all[$i].id] = $i else . end)) as $pos
| [ range(0; length) as $i
    | $all[$i] as $e
    | ($e.id | if type == "string" then . else "entry #\($i)" end) as $who
    | (
        (["id", "name", "type"][] as $k
          | select(($e[$k] | nonempty) | not)
          | "ERROR \($who): missing or empty \"\($k)\""),
        (select(($e.id | type) == "string" and ($e.id | test("^[a-z0-9][a-z0-9_-]*$") | not))
          | "ERROR \($who): id must match [a-z0-9][a-z0-9_-]*"),
        (select(($e.type | nonempty) and (["package", "dependency"] | index($e.type) | not))
          | "ERROR \($who): type must be \"package\" or \"dependency\""),
        (($e.repo | if type == "object" then .url else null end) as $u
          | select(($u | nonempty) | not)
          | "ERROR \($who): missing repo.url"),
        (($e.repo | if type == "object" then .branch else null end) as $b
          | select($b != null and ($b | type) != "string")
          | "ERROR \($who): repo.branch must be a string"),
        (($e.repo | if type == "object" then .commit else null end) as $b
          | select($b != null and ($b | type) != "string")
          | "ERROR \($who): repo.commit must be a string"),
        (["author", "description", "directory"][] as $k
          | select($e[$k] != null and ($e[$k] | type) != "string")
          | "ERROR \($who): \"\($k)\" must be a string"),
        (["patches"][] as $k
          | select($e[$k] != null and ($e[$k] | type) != "boolean")
          | "ERROR \($who): \"\($k)\" must be a boolean"),
        (select(($e.directory | type) == "string" and ($e.directory | test("^[A-Za-z0-9][A-Za-z0-9._-]*$") | not))
          | "ERROR \($who): directory must be a plain directory name"),
        (select($e.dependencies != null and ($e.dependencies | strs | not))
          | "ERROR \($who): dependencies must be an array of ids"),
        (select($e.config_file_scheme != null and ([0, 1, 2, 3] | index($e.config_file_scheme) | not))
          | "ERROR \($who): config_file_scheme must be 0, 1, 2 or 3"),
        (select($e.env != null and (($e.env | type) != "object" or ($e.env | to_entries | any(.value | type != "string"))))
          | "ERROR \($who): env must be an object of strings"),
        (($e.env | if type == "object" then keys[] else empty end) as $k
          | select($k | test("^[A-Za-z_][A-Za-z0-9_]*$") | not)
          | "ERROR \($who): invalid env name \"\($k)\""),
        (["build_script", "install_script"][] as $k
          | select($e[$k] != null and ($e[$k] | type) != "string" and ($e[$k] | strs | not))
          | "ERROR \($who): \"\($k)\" must be a string or an array of strings"),
        (select($e.config_options != null and ($e.config_options | type) != "object")
          | "ERROR \($who): config_options must be an object"),
        (($e.config_options | if type == "object" then to_entries[] else empty end) as $o
          | select(($o.value | type) != "object")
          | "ERROR \($who): config_options.\($o.key) must be an object"),
        (($e.config_options | if type == "object" then to_entries[] else empty end) as $o
          | select(($o.value | type) == "object")
          | (($o.value.dependencies // []) | if strs then .[] else empty end) as $d
          | select($pos[$d] == null)
          | "ERROR \($who): config_options.\($o.key) depends on unknown id \"\($d)\""),
        ((($e.dependencies // []) | if strs then .[] else empty end) as $d
          | if $pos[$d] == null then "ERROR \($who): unknown dependency \"\($d)\""
            elif $pos[$d] >= $i then "ERROR \($who): dependency \"\($d)\" has to be listed before it"
            else empty end),
        (($e | keys[]) as $k
          | select($k == "overlay_directory")
          | "WARN \($who): \"overlay_directory\" is deprecated and ignored"),
        (($e | keys[]) as $k
          | select($k != "//" and $k != "overlay_directory" and ((known | index($k)) == null))
          | "WARN \($who): unknown key \"\($k)\" (ignored)")
      )
  ]
  + [ $all | map(select((.id | type) == "string")) | group_by(.id)[] | select(length > 1) | "ERROR duplicate id \"\(.[0].id)\"" ]
| .[]
EOF

read -r -d '' NORMALIZE_JQ <<'EOF'
def lines: if type == "string" then [.] else . end;

map({
  name,
  id,
  type,
  author: (.author // ""),
  description: (.description // ""),
  dependencies: (.dependencies // []),
  repo: { url: .repo.url, branch: (.repo.branch // ""), commit: (.repo.commit // "") },
  directory: (.directory // .id),
  patches: (.patches // false),
  config_file_scheme: (.config_file_scheme // 0),
  env: (.env // {}),
  build_script: ((.build_script // []) | lines),
  install_script: ((.install_script // []) | lines)
} + (if .config_options != null then { config_options } else {} end))
EOF

main() {
  local text line lineno=0 merged message errors=0

  ENTRIES_FILE="$(mktemp)"
  trap 'rm -f "${ENTRIES_FILE}" "${OUT_FILE}.tmp"' EXIT

  strip_comments "$(<"${PRE_FILE}")"
  text="${REPLY}"

  while IFS= read -r line; do
    lineno=$((lineno + 1))
    [[ -z "${line//[[:space:]]/}" ]] && continue

    if [[ "${line}" =~ ${INCLUDE_RE} ]]; then
      resolve_include_path "${BASH_REMATCH[1]}" "${MANIFEST_DIR}"
      resolve_file "${REPLY}" 1 ":${PRE_FILE}"
    else
      error 1 "${PRE_FILE}:${lineno}: only #include \"...\"; lines and /* */ comments are allowed"
    fi
  done <<<"${text}"

  merged="$(jq -s '.' "${ENTRIES_FILE}")" || error 1 "failed to merge entries"

  local validate_out
  validate_out="$(mktemp)"
  jq -r "${VALIDATE_JQ}" <<<"${merged}" > "${validate_out}" || true
  while IFS= read -r message; do
    case "${message}" in
      "ERROR "*) log "ERROR" "${message#ERROR }"; errors=$((errors + 1)) ;;
      "WARN "*)  log "WARN" "${message#WARN }" ;;
    esac
  done < "${validate_out}"
  rm -f "${validate_out}"
  [[ "${errors}" -eq 0 ]] || error 1 "manifest has ${errors} error(s)"

  mkdir -p "$(dirname "${OUT_FILE}")"
  jq "${NORMALIZE_JQ}" <<<"${merged}" > "${OUT_FILE}.tmp" || error 1 "failed to normalize manifest"
  mv "${OUT_FILE}.tmp" "${OUT_FILE}"

  log "GEN" "${OUT_FILE}"
}

main "$@"
