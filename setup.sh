#!/bin/bash
SRC_DIR="$(realpath $(dirname -- "${BASH_SOURCE[0]}"))"

link_dir() {
    SRC=$1; DEST=$2;
    mkdir -p "${DEST}"
    for file in ${SRC_DIR}/${SRC}/*; do
        file_dest="${DEST}"/$(basename ${file})
        (
            set -x
            ln -sf "${file}" "${file_dest}"
        )
    done
}

link() {
    SRC=$(realpath ${1}); DEST=$(realpath ${2});
    (
        set -x
        ln -sf "${SRC}" "${DEST}"
    )
}

ask() {
    ## Ask the user a question and set the given variable name with their answer
    ## If the answer is blank, repeat the question.
    local __prompt="${1}"; local __var="${2}"; local __default="${3}"
    while true; do
        read -e -p "${__prompt}"$'\x0a\e[32m:\e[0m ' -i "${__default}" ${__var}
        export ${__var}
        [[ -z "${!__var}" ]] || break
    done
}

git_config() {
    local GIT_USERNAME GIT_EMAIL
    echo "## Setting up global git client config (~/.gitconfig) ..."
    if ! git config --global user.name >/dev/null; then
        ask "Enter your git name (eg. John Doe)" GIT_USERNAME
        git config --global user.name "${GIT_USERNAME}"
    fi
    if ! git config --global user.email >/dev/null; then
        ask "Enter your git email address (eg. you@example.com)" GIT_EMAIL
        git config --global user.email "${GIT_EMAIL}"
    fi
    if ! git config --global pull.rebase >/dev/null; then
        git config --global pull.rebase false
    fi
    if ! git config --global init.defaultBranch >/dev/null; then
        git config --global init.defaultBranch master
    fi
    echo
    cat ~/.gitconfig
    echo 
}

link_dir config ${HOME}/.config
link_dir bin ${HOME}/bin
link bash_profile ${HOME}/.bash_profile
link bashrc ${HOME}/.bashrc
link inputrc ${HOME}/.inputrc
git_config
