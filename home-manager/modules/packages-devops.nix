{ pkgs }:

# DevOps: containers, orchestration, VM / infra tooling. Part of the
# `dotfiles` profile.

with pkgs; [
  docker
  kubectl
  talosctl
  ansible
  distrobox
  quickemu
  natscli
]
