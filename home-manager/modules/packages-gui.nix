{ pkgs }:

# Wayland / Sway desktop user packages. Only installed with the `sway`
# profile; the CLI toolbox in packages.nix comes with `dotfiles`.

with pkgs; [
  foot                    # terminal
  waybar                  # status bar
  rofi                    # launcher
  grim                    # screenshot
  slurp                   # region select
  sway-contrib.grimshot   # screenshot helper
  wl-clipboard            # clipboard
  wdisplays               # display layout GUI
  nerd-fonts.jetbrains-mono
]
