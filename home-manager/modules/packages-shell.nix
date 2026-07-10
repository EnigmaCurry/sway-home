{ pkgs }:

# Interactive shell UX: modern CLI replacements, TUI monitors, pipe
# helpers. Part of the `dotfiles` profile.

with pkgs; [
  fzf
  bat
  eza
  ripgrep
  ripgrep-all
  jq
  btop
  duf
  ncdu
  dust
  tmux
  pv
  moreutils
]
