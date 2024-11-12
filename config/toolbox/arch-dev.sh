#!/bin/bash
set -e
IMAGE=arch
PACKAGES=(
    base-devel
    chromium
    docker
    gimp
    git
    go
    inetutils
    keychain
    less 
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    noto-fonts-extra
    direnv
)

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

build_image() {
    local IMAGE=${IMAGE:-arch}
    (set -e
     TMP=$(mktemp -d)
     cd ${TMP}
     cat << 'EOF' > Dockerfile
## http://book.rymcg.tech/linux-workstation/config/toolbox/#arch-linux-toolbox
FROM docker.io/archlinux/archlinux:latest
LABEL com.github.containers.toolbox="true" name=${IMAGE}-toolbox
RUN pacman -Sy --noconfirm archlinux-keyring && \
    pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Syu --noconfirm && \
    pacman  -S --noconfirm sudo && \
    pacman -Scc --noconfirm && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/toolbox
CMD ["bash"]
EOF
     podman build -t ${IMAGE} .
     cd ..
     rm -rf "${TMP}"
    )
}

arch_setup_host_spawn() {
    if ! command -v host-spawn; then
        (set -e
         BUILD_DIR=$(mktemp -d)
         cat << 'EOF' > ${BUILD_DIR}/PKGBUILD
pkgname=host-spawn-git
pkgver=v1.6.0.r0.ge150d2c
pkgrel=1
pkgdesc='Run commands on your host machine from inside your flatpak sandbox, toolbox or distrobox containers.'
arch=('any')
url="https://github.com/1player/host-spawn"
license=('MIT-0')
source=("${pkgname%-git}::git+https://github.com/1player/host-spawn.git")
depends=('go')
makedepends=('git')
conflicts=("${pkgname%-git}")
provides=("${pkgname%-git}")
package() {
  cd "${pkgname%-git}"
  ./build.sh $(uname -m)
  install -Dm 555 build/host-spawn-$(uname -m) \
    "${pkgdir}"/usr/bin/host-spawn
}
pkgver() {
  cd "${pkgname%-git}"
  git describe --long --tags | sed 's/\([^-]*-g\)/r\1/;s/-/./g'
}
sha256sums=('SKIP')
EOF
         chown -R nobody ${BUILD_DIR}
         cd ${BUILD_DIR}
         sudo -u nobody HOME=${BUILD_DIR} makepkg
         sudo pacman -U host-spawn-*.zst --noconfirm
         cd /tmp
         rm -rf ${BUILD_DIR}
        )
    fi
    setup_host_spawn
}

setup_yay() {
    if ! command -v yay; then
        local TMP=$(mktemp -d)
        chown nobody ${TMP}
        sudo -u nobody git clone https://aur.archlinux.org/yay-bin.git ${TMP}/yay \
            && cd ${TMP}/yay \
            && sudo -u nobody HOME=${TMP} makepkg -s \
            && pacman -U --noconfirm yay-bin-*.pkg.tar.zst
        cd /tmp
        rm -rf ${BUILD_DIR}
    fi
}

enable_multilib() {
  local pacman_conf="/etc/pacman.conf"

  if ! grep -q "^\[multilib\]" "$pacman_conf"; then
    echo "Adding [multilib] repository to $pacman_conf..."
    sudo tee -a "$pacman_conf" > /dev/null << EOF

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
    echo "[multilib] repository added successfully."
    echo "Updating package database..."
    sudo pacman -Syu
  else
    echo "[multilib] repository is already present."
  fi
}

enable_radeon_graphics() {
  if lspci | grep -iq "vga.*amd" || lspci | grep -iq "vga.*radeon"; then
    echo "AMD Radeon graphics card detected. Installing vulkan-radeon..."
    sudo pacman -S vulkan-radeon lib32-vulkan-radeon --noconfirm
  else
    echo "No AMD Radeon graphics card detected."
  fi
}

setup_arch() {
    check_os_id "arch"
    sudo pacman -Syu --noconfirm
    sudo pacman -S --noconfirm "${PACKAGES[@]}"
    arch_setup_host_spawn

    setup_yay
    enable_multilib
    enable_radeon_graphics
}

if ! is_container; then
    build_image
fi
main setup_arch "${BASH_SOURCE}" "${IMAGE}"
