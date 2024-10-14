#!/bin/bash
set -e

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../bash/funcs.sh"

if ! grep -q '^ID=fedora' /etc/os-release || \
        ([[ ! -e /run/.containerenv ]] && [[ ! -e /.dockerenv ]]); then
  fault "This script can only run inside of a Fedora container."
fi

echo
confirm no "This will configure a fresh Fedora development environment"

set -x
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
