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
    git-lfs
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
    poppler-glib
    libpng
    zlib
    libpng-devel
    poppler-devel
    poppler-glib-devel
    zlib-devel
    pkgconf
    direnv
#    texlive-collection-basic
#    texlive-latex
#    texlive-latex-bin
#    texlive-texliveonfly
#    texlive-unicode-math
    mpv
    python-black
    libtool
    hidapi-devel
    libusb1-devel
    mesa-libGL-devel
    jack-audio-connection-kit-devel
    libXcursor-devel
    cmake
    @development-tools
    openssl-devel
    xcb-util-wm-devel
    gcc-aarch64-linux-gnu
    sysroot-aarch64-fc41-glibc
    ghostscript-tools-dvipdf
    sqlite-devel
)

setup_fedora() {
    check_os_id "fedora"
    sudo dnf upgrade -y
    sudo dnf install -y "${PACKAGES[@]}"
    setup_host_spawn
    get_docker
}

main setup_fedora "${BASH_SOURCE}"
