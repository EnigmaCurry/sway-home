{ pkgs }:

# Miscellaneous CLI / TUI user packages that don't fit a topical split.
# Categorized packages live in packages-{dev,devops,net,shell,media}.nix;
# Wayland/desktop packages live in packages-gui.nix. Part of the
# `dotfiles` profile.

with pkgs; [
  keychain
  ispell
  conceal
  unar
  irssi
  rlwrap
]
