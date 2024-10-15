#!/bin/bash
set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

setup_fedora() {
    packages=(
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
    )

    sudo dnf upgrade -y
    sudo dnf install -y "${packages[@]}"
    sudo dnf groupinstall -y "Development Tools" "Development Libraries"

    sudo ln -sf /usr/bin/flatpak-xdg-open /usr/local/bin/xdg-open
    sudo ln -sf /usr/bin/host-spawn /usr/local/bin/toolbox
    sudo ln -sf /usr/bin/host-spawn /usr/local/bin/podman
    sudo ln -sf /usr/bin/host-spawn /usr/local/bin/flatpak

    if ! command -v docker >/dev/null; then
        curl -sSL https://get.docker.com | sh
    fi
}

main setup_fedora "${BASH_SOURCE}"
