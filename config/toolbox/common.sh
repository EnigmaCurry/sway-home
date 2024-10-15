#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../bash/funcs.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

create_toolbox_container() {
    local NAME=$1
    local SCRIPT=$2
    check_var NAME SCRIPT
    toolbox create "${NAME}"
    podman start "${NAME}"
    podman exec --env NO_CONFIRM=true "${NAME}" /bin/bash -c "cd ${SCRIPT_DIR} && ./$(basename ${SCRIPT})"
}


main() {
    local CALLBACK=$1
    local SCRIPT=$2
    check_var CALLBACK SCRIPT 
    if [[ -e /run/.containerenv ]] || [[ -e /.dockerenv ]]; then
        # Running in a container ..
        echo
        NO_CONFIRM=${NO_CONFIRM:-false}
        if [[ "${NO_CONFIRM}" != "true" ]]; then
            confirm no "This script will reinstall all container packages and config"
        fi
        set -x
        ${CALLBACK}
        set +x
        echo
        echo "Container setup complete."
    else
        # Create a new container:
        if [[ -z "${NAME}" ]]; then
            ask_no_blank "What do you want to name the container?" NAME dev
        fi
        if podman container inspect ${NAME} >/dev/null 2>&1; then
            fault "Container '${NAME}' already exists."
        else
            confirm yes "This will create a new container named ${NAME}"
            create_toolbox_container "${NAME}" "${SCRIPT}"
        fi
    fi
}
