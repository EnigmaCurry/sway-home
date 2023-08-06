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
    SRC=$(realpath ${1}); DEST=${2};
    (
        set -x
        ln -sf "${SRC}" "${DEST}"
    )
}

link_dir config ${HOME}/.config
link_dir bin ${HOME}/bin
link bash_profile ${HOME}/.bash_profile
link bashrc ${HOME}/.bashrc
link inputrc ${HOME}/.inputrc

