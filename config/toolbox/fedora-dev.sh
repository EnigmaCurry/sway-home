#!/bin/bash
set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
PACKAGES=(
    bash
    bind-utils
    curl
    emacs
    flatpak-xdg-utils
    gettext
    gettext
    git
    go
    host-spawn
    htop
    httpd-tools
    hugo
    inotify-tools
    jq
    keychain
    libwebp-tools
    make
    openssl
    pulseaudio-utils
    sshfs
    w3m
    wireguard-tools
    xdg-utils
    ffmpeg-free
)

setup_fedora() {
    check_os_id "fedora"
    sudo dnf upgrade -y
    sudo dnf install -y "${PACKAGES[@]}"
    sudo dnf groupinstall -y "Development Tools" "Development Libraries"
    setup_host_spawn
    get_docker
}

main setup_fedora "${BASH_SOURCE}"
