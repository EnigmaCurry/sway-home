#!/usr/bin/env bash
set -eo pipefail

MACHINE="$1"
MACHINE_DIR="nixos/build-iso/$MACHINE"

if [[ -z "${MACHINE}" ]]; then
    echo "usage: build-iso.sh <MACHINE>"
    exit 1
fi

if [[ ! -d ${MACHINE_DIR} ]]; then
    echo "Machine directory does not exist: ${MACHINE_DIR}"
    exit 1
fi

if [[ ! -f ${MACHINE_DIR}/flake.nix ]]; then
    echo "Machine flake.nix does not exist: ${MACHINE_DIR}/flake.nix"
    exit 1
fi

nix build "path:${MACHINE_DIR}#iso" --extra-experimental-features "nix-command flakes"
