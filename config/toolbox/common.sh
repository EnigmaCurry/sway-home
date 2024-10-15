#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../bash/funcs.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

is_podman() {
    test -e /run/.containerenv
}

is_docker() {
    test -e /.dockerenv
}

is_toolbox() {
    test -f /run/.toolboxenv
}

is_container() {
    if is_podman || is_docker; then
        return 0
    else
        return 1
    fi
}

get_os_id() {
    awk -F= '/^ID=/{print $2}' /etc/os-release
}

check_os_id() {
    (set +x;
     echo
     local id=$1;
     check_var id
     grep "^ID=${id}$" /etc/os-release &>/dev/null || \
         fault "Container is not running ${id}."
    )
}


setup_host_spawn() {
    if [[ ! -f /usr/bin/host-spawn ]]; then
        echo
        fault "/usr/bin/host-spawn not found."
    fi
    if [[ -f /usr/bin/flatpak-xdg-open ]]; then
        sudo ln -sf /usr/bin/flatpak-xdg-open /usr/local/bin/xdg-open
    fi
    sudo ln -sf /usr/bin/host-spawn /usr/local/bin/toolbox
    sudo ln -sf /usr/bin/host-spawn /usr/local/bin/podman
    sudo ln -sf /usr/bin/host-spawn /usr/local/bin/flatpak
}

get_docker() {
    ## not all OS/archiectures supported
    if ! command -v docker; then
        curl -sSL https://get.docker.com | sh
    fi
}

run_container_script() {
    local NAME=$1
    local SCRIPT=$2
    check_var NAME SCRIPT_DIR SCRIPT
    podman exec \
           --env NAME="${NAME}" \
           --env NO_CONFIRM=true \
           "${NAME}" \
           /bin/bash -c "cd ${SCRIPT_DIR} && ./$(basename ${SCRIPT})"
    
}

create_toolbox_container() {
    local NAME=$1; shift
    local SCRIPT=$1; shift
    local IMAGE_ARG="$@"
    check_var NAME SCRIPT
    toolbox create "${NAME}" ${IMAGE_ARG}
    podman start "${NAME}"
    set -x
    run_container_script ${NAME} ${SCRIPT}
}


main() {
    local CALLBACK=$1
    local SCRIPT=$2
    local IMAGE=$3
    local IMAGE_ARG=""
    check_var CALLBACK SCRIPT
    if [[ -n "${IMAGE}" ]]; then
        IMAGE_ARG="--image ${IMAGE}"
    fi
    if is_container; then
        # Running in a container ..
        check_var NAME
        echo "## Detected container environment"
        NO_CONFIRM=${NO_CONFIRM:-false}
        # if [[ "${NO_CONFIRM}" != "true" ]]; then
        #     confirm no "This script will reinstall all container packages and config"
        # fi
        set -x
        ${CALLBACK}
        set +x
        echo
        echo "Container setup complete."
        if is_toolbox; then
            echo "Enter the toolbox container:"
            echo " toolbox enter ${NAME}"
        fi
    else
        # Create a new container:
        if [[ -z "${NAME}" ]]; then
            ask_no_blank "What do you want to name the container?" NAME ${IMAGE}
        fi
        if podman container inspect ${NAME} >/dev/null 2>&1; then
            stderr ""
            local CHOSEN=$(choose -n "Container '${NAME}' already exists. How do you want to proceed?" \
                           "Update the existing container." \
                           "Remove the container and create a new one from scratch." \
                           "Cancel.")
            case "$CHOSEN" in
                0)
                    # Update the existing container
                    echo "Updating existing container ..."
                    debug_var SCRIPT
                    run_container_script "${NAME}" "${SCRIPT}"
                    ;;
                1)
                    # Remote the container and create a new one
                    echo "Removing container ..."
                    podman rm -f "${NAME}"
                    create_toolbox_container "${NAME}" "${SCRIPT}" "${IMAGE_ARG}"
                    ;;
                2)
                    # Quit
                    cancel
                    ;;
                *)
                    cancel
                    ;;
            esac
        else
            confirm yes "This will create a new container named ${NAME}"
            create_toolbox_container "${NAME}" "${SCRIPT}" "${IMAGE_ARG}"
        fi
    fi
}
