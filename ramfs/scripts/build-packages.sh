#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}"/lib/common.sh
[[ "${VERBOSE}" == 1 ]] && set -x

MANIFEST_JSON="$1"
PACKAGE_DIR="$2"
PACKAGE_DIR="/${PACKAGE_DIR#/}"

require_arg "${MANIFEST_JSON}" "manifest json"
require_arg "${PACKAGE_DIR}" "package directory"

# PROJECT_DIR is passed to us by the Makefile
source "${PROJECT_DIR}/scripts/lib/generated/config.sh"

main() {
  [[ "${CONFIG_PACKAGES}" != "y" ]] && echo "pkg not enabled" && exit 0

  echo "-- We're about to start building packages! If you want to quit now, press CTRL+C to cancel the build flow, otherwise Press Enter to Continue... --"
  read -r

  jq -c '.[]' "${MANIFEST_JSON}" | while IFS= read -r package_json; do
    # Used by builder? Yes
    package_name=$(echo "${package_json}" | jq -r '.name')
    # Used by builder? Yes
    package_package_name=$(echo "${package_json}" | jq -r '.package_name')
    # Used by builder? No
    package_author=$(echo "${package_json}" | jq -r '.author')
    # Used by builder? No
    package_description=$(echo "${package_json}" | jq -r '.description')
    # Used by builder? Yes
    package_repo_url=$(echo "${package_json}" | jq -r '.repo_url')
    # Used by builder? Yes
    package_repo_branch=$(echo "${package_json}" | jq -r '.repo_branch')
    # Used by builder? Yes
    package_directory=$(echo "${package_json}" | jq -r '.directory')
    # Used by builder? Yes
    package_patch_directory=$(echo "${package_json}" | jq -r '.patch_directory')
    # Used by builder? No
    package_overlay_directory=$(echo "${package_json}" | jq -r '.overlay_directory')
    # Used by builder? Yes
    package_config_file=$(echo "${package_json}" | jq -r '.config_file // 0')


    # these are arrays, we need to handle them differently.
    # Used by builder? Yes
    package_dependencies=$(echo "${package_json}" | jq -r '.dependencies | join(" ")')
    # Used by builder? Yes
    package_build_cmd=$(echo "${package_json}" | jq -r '.build_cmd | join("\n")')
    
    pkgdir=""
    gitargs=()

    ## config name schemes
    config_scheme_0=""
    config_scheme_1="/${project_dir}/configs/ramfs/${package_package_name}/config.${CONFIG_ARCH_SELECTION}"
    config_scheme_2="/${project_dir}/configs/ramfs/${package_package_name}/config.cross.$(uname -m)-${CONFIG_ARCH_SELECTION}"

    case "${package_name}" in
      (*[!a-zA-Z0-9_-]*)
        echo "skipping package with invalid name. pass VERBOSE=1 to 'make' to see the full name."
        continue
        ;;
    esac

    # Is the package disabled?
    eval "[ \"\$CONFIG_PACKAGE_${package_package_name}\" != \"y\" ]" && continue

    log "GIT" "${package_name}"
    mkdir -p "${PACKAGE_DIR}"
    cd "${PACKAGE_DIR}"
    
    # There wasn't a repo url specified. That means this is 
    # an invalid package entry, skip it.
    [ -z "${package_repo_url}" ] && continue

    if [ ! -z "${package_repo_branch}" ]; then
      gitargs+=(-b "${package_repo_branch}")
    fi

    # This MUST be the last argument passed to git.
    if [ ! -z "${package_directory}" ]; then
      gitargs+=("${package_directory}")
      pkgdir="${PACKAGE_DIR}/${package_directory}"
    else
      gitargs+=("${package_name}")
      pkgdir="${PACKAGE_DIR}/${package_name}"
    fi

    git clone "${package_repo_url}" "${gitargs[@]}"

    cd "${pkgdir}"
    
    # Should we apply patches?
    if [ ! -z "${package_patch_directory}" ]; then
      patchdir="/${project_dir}/patches/ramfs/${package_patch_directory}/"
      if [ ! -d "${patchdir}" ]; then
        log "ERR" "patch dir for ${package_package_name} doesn't exist!"
        continue
      fi
      for patchFile in "${patchdir}"/*; do
        # patchdir is empty, skip it.
        [ -e "${patchFile}" ] || continue

        patch_name=$(basename "${patchFile}")
        marker_file="${PACKAGE_DIR}/.marker/${package_package_name}/patches/${patch_name}.applied"
        mkdir -p "$(dirname "${marker_file}")" 2>/dev/null || true # just in case
        
        if [ -f "${marker_file}" ]; then
          log "INFO" "patch ${patch_name} is already applied"
        else
          log "INFO" "applying ${patch_name}"
          if patch -p1 -N --batch --ignore-whitespace -d "${pkgdir}" < "${patchFile}"; then
            touch "${marker_file}"
          else
            log "ERR" "failed to apply patch ${patch_name}"
            exit 1
          fi
        fi
      done
    fi

    # Do we have a config file?
    if [ "${package_config_file}" != "0" ]; then
      cfg_file="${config_scheme_0}"
      case "${package_config_file}" in
        0)
          log "WARN" "config file disabled, how did we get here?"
          ;;
        1)
          cfg_file="${config_scheme_1}"
          ;;
        2)
          cfg_file="${config_scheme_2}"
          ;;
        3)
          if [ "${CONFIG_ARCH_SELECTION}" != "$(uname -m)" ]; then
            cfg_file="${config_scheme_2}"
          elif [ "${CONFIG_ARCH_SELECTION}" == "$(uname -m)" ]; then
            cfg_file="${config_scheme_1}"
          else
            # what??? how did we get here..
            log "ERR" "something didn't return correctly!!"
            log "ERR" "This is a bug! Please report it on the ${project_name} GitHub."
            log "ERR" "CONFIG_ARCH_SELECTION: ${CONFIG_ARCH_SELECTION}"
            log "ERR" "HOST_ARCH: $(uname -m)"
            exit 1
          fi
          ;;
        *)
          log "ERR" "invalid config file entry, assuming no config."
          ;;
      esac

      if [ ! -z "${cfg_file}" ]; then
        if [ ! -f "${cfg_file}" ]; then
          log "ERR" "config file for ${package_package_name} doesn't exist!"
          log "ERR" "cfg_file: ${cfg_file}"
          log "ERR" "${CONFIG_ARCH_SELECTION} & $(uname -m) & ${config_scheme_0} & ${config_scheme_1} & ${config_scheme_2} & ${cfg_file} & ${package_config_file}"
          log "ERR" "this could cause unexpected behavior."
          read -rep "Do you want to continue? You may encounter errors. [y/N] " ans
          if [ "${ans}" != "y" ] && [ "${ans}" != "Y" ]; then
            log "INFO" "skipping ${package_package_name}"
            continue
          fi
        fi
      
        cp "${cfg_file}" "${PACKAGE_DIR}/${package_directory}/.config"
      fi
    fi


    # Everything should be good to go, we can
    # finally start building the package.
    cd "${PACKAGE_DIR}/${package_directory}"
    source ~/.bashrc # we need PATH..
    eval "${package_build_cmd}"
  done
}

main "$@"
