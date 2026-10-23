#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}"/lib/common.sh
[[ "${VERBOSE}" == 1 ]] && set -x

# usage: build-packages.sh <expanded manifest.json (from parse-manifest.sh)> <package dir>
MANIFEST_JSON="$1"
PACKAGE_DIR="$2"

require_arg "${MANIFEST_JSON}" "manifest json"
require_arg "${PACKAGE_DIR}" "package directory"
PACKAGE_DIR="/${PACKAGE_DIR#/}"
PACKAGE_DIR="${PACKAGE_DIR%/}"

# PROJECT_DIR is passed to us by the Makefile
source "${PROJECT_DIR}/scripts/lib/generated/config.sh"

apply_patches() {
  local name="$1" id_upper="$2" pkgdir="$3" patchdir="$4"
  local patchFile patch_name marker_file

  if [ ! -d "${patchdir}" ]; then
    log "ERR" "patch dir for ${name} doesn't exist!"
    log "ERR" "patchdir: ${patchdir}"
    return 1
  fi

  for patchFile in "${patchdir}"/*; do
    # patchdir is empty, skip it.
    [ -e "${patchFile}" ] || continue

    patch_name=$(basename "${patchFile}")
    marker_file="${PACKAGE_DIR}/.marker/${id_upper}/patches/${patch_name}.applied"
    mkdir -p "$(dirname "${marker_file}")" 2>/dev/null || true

    if [ -f "${marker_file}" ]; then
      log "INFO" "patch ${patch_name} is already applied"
    else
      log "INFO" "applying ${patch_name}"
      if patch -p1 -N --batch --ignore-whitespace -d "${pkgdir}" < "${patchFile}"; then
        touch "${marker_file}"
      else
        log "ERR" "failed to apply patch ${patch_name}"
        return 1
      fi
    fi
  done
}

# prints the config file to use for this package, or nothing for scheme 0
config_file_for() {
  local id_upper="$1" scheme="$2"
  local dir="${project_dir}/configs/ramfs/${id_upper}"

  case "${scheme}" in
    0) ;;
    1) echo "${dir}/config.${CONFIG_ARCH_SELECTION}" ;;
    2) echo "${dir}/config.cross.$(uname -m)-${CONFIG_ARCH_SELECTION}" ;;
    3)
      if [ "${CONFIG_ARCH_SELECTION}" != "$(uname -m)" ]; then
        echo "${dir}/config.cross.$(uname -m)-${CONFIG_ARCH_SELECTION}"
      else
        echo "${dir}/config.${CONFIG_ARCH_SELECTION}"
      fi
      ;;
    *) log "ERR" "invalid config file scheme '${scheme}', assuming no config." >&2 ;;
  esac
}

# REQUIRED_DEPS: space-separated list of dependency ids that must be built
# (computed by compute_required_deps before the build loop).
REQUIRED_DEPS=""

# Returns 0 if this entry should be built:
# - packages: only when CONFIG_PACKAGE_<ID>=y
# - dependencies: only when they are required by at least one enabled package
should_build() {
  local entry="$1" id typ id_upper cfgvar
  id="$(jq -r '.id' <<<"${entry}")"
  typ="$(jq -r '.type' <<<"${entry}")"
  id_upper="${id^^}"
  id_upper="${id_upper//-/_}"

  if [[ "${typ}" == "package" ]]; then
    cfgvar="CONFIG_PACKAGE_${id_upper}"
    [[ "${!cfgvar}" == "y" ]]
    return $?
  fi

  # dependency: build only if listed in REQUIRED_DEPS
  case " ${REQUIRED_DEPS} " in
    *" ${id} "*) return 0 ;;
    *) return 1 ;;
  esac
}

build_package() {
  local entry="$1"
  local id id_upper name repo_url repo_branch directory patches_bool config_scheme
  local build_script install_script pkgdir cfg_file ans
  local -a gitargs=()

  should_build "${entry}" || return 0

  id="$(jq -r '.id' <<<"${entry}")"
  name="$(jq -r '.name' <<<"${entry}")"
  repo_url="$(jq -r '.repo.url' <<<"${entry}")"
  repo_branch="$(jq -r '.repo.branch' <<<"${entry}")"
  directory="$(jq -r '.directory' <<<"${entry}")"
  patches_bool="$(jq -r '.patches' <<<"${entry}")"
  config_scheme="$(jq -r '.config_file_scheme' <<<"${entry}")"
  build_script="$(jq -r '.build_script | join("\n")' <<<"${entry}")"
  install_script="$(jq -r '.install_script | join("\n")' <<<"${entry}")"

  id_upper="${id^^}"
  id_upper="${id_upper//-/_}"
  pkgdir="${PACKAGE_DIR}/${directory}"


  mkdir -p "${PACKAGE_DIR}"
  cd "${PACKAGE_DIR}" || return 1

  if [ -d "${pkgdir}/.git" ]; then
    log "GIT" "${name} (exists)"
  else
    log "GIT" "${name}"
    [ -n "${repo_branch}" ] && gitargs+=(-b "${repo_branch}")
    git clone "${repo_url}" "${gitargs[@]}" "${directory}" || {
      log "ERR" "failed to clone ${name}"
      return 1
    }
  fi

  cd "${pkgdir}" || return 1

  if [ "${patches_bool}" == "true" ]; then
    apply_patches "${name}" "${id_upper}" "${pkgdir}" "${PROJECT_DIR}/patches/ramfs/${id}" || return 1
  fi

  cfg_file="$(config_file_for "${id_upper}" "${config_scheme}")"
  if [ -n "${cfg_file}" ]; then
    if [ ! -f "${cfg_file}" ]; then
      log "ERR" "config file for ${name} doesn't exist!"
      log "ERR" "cfg_file: ${cfg_file}"
      log "ERR" "this could cause unexpected behavior."
      read -rep "Do you want to continue? You may encounter errors. [y/N] " ans
      if [ "${ans}" != "y" ] && [ "${ans}" != "Y" ]; then
        log "INFO" "skipping ${name}"
        return 0
      fi
    else
      cp "${cfg_file}" "${pkgdir}/.config"
    fi
  fi

  source ~/.bashrc 2>/dev/null || true

  if [ -n "${build_script}" ]; then
    log "BUILD" "${name}"
    eval "${build_script}" || {
      log "ERR" "build failed for ${name}"
      return 1
    }
  fi

  if [ -n "${install_script}" ]; then
    log "INSTALL" "${name}"
    eval "${install_script}" || {
      log "ERR" "install failed for ${name}"
      return 1
    }
  fi
}

# Walk the dependency graph of every enabled package and collect the set of
# dependency ids that must be built. Expands transitively.
compute_required_deps() {
  local entry id typ id_upper cfgvar dep
  local -A needed=()
  local -a queue=()

  # seed queue with direct deps of enabled packages
  while IFS= read -r entry; do
    id="$(jq -r '.id' <<<"${entry}")"
    typ="$(jq -r '.type' <<<"${entry}")"
    [[ "${typ}" == "package" ]] || continue
    id_upper="${id^^}"
    id_upper="${id_upper//-/_}"
    cfgvar="CONFIG_PACKAGE_${id_upper}"
    [[ "${!cfgvar}" == "y" ]] || continue
    while IFS= read -r dep; do
      [[ -z "${dep}" ]] && continue
      if [[ -z "${needed[${dep}]+set}" ]]; then
        needed["${dep}"]=1
        queue+=("${dep}")
      fi
    done < <(jq -r '.dependencies[]?' <<<"${entry}")
  done < <(jq -c '.[]' "${MANIFEST_JSON}")

  # expand transitively (deps of deps)
  while [[ ${#queue[@]} -gt 0 ]]; do
    local cur="${queue[0]}"
    queue=("${queue[@]:1}")
    entry="$(jq -c --arg id "${cur}" '.[] | select(.id == $id)' "${MANIFEST_JSON}")"
    [[ -n "${entry}" ]] || continue
    while IFS= read -r dep; do
      [[ -z "${dep}" ]] && continue
      if [[ -z "${needed[${dep}]+set}" ]]; then
        needed["${dep}"]=1
        queue+=("${dep}")
      fi
    done < <(jq -r '.dependencies[]?' <<<"${entry}")
  done

  REQUIRED_DEPS=""
  for id in "${!needed[@]}"; do
    REQUIRED_DEPS="${REQUIRED_DEPS} ${id}"
  done
}

main() {
  local entry

  [[ "${CONFIG_PACKAGES}" != "y" ]] && echo "pkg not enabled" && exit 0

  echo "-- We're about to start building packages! If you want to quit now, press CTRL+C to cancel the build flow, otherwise Press Enter to Continue... --"
  read -r

  compute_required_deps
  log "DEPS" "required: ${REQUIRED_DEPS:-none}"

  while IFS= read -r -u 3 entry; do
    build_package "${entry}" || exit 1
  done 3< <(jq -c '.[]' "${MANIFEST_JSON}")
}

main "$@"
