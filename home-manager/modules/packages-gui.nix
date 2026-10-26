{ pkgs }:

# Wayland / Sway desktop user packages. Only installed with the `sway`
# profile; the CLI toolbox (packages-{dev,devops,net,shell,media}.nix)
# comes with `dotfiles`.

with pkgs; [
  foot                    # terminal
  waybar                  # status bar
  rofi                    # launcher
  grim                    # screenshot
  slurp                   # region select
  sway-contrib.grimshot   # screenshot helper
  wl-clipboard            # clipboard
  wdisplays               # display layout GUI
  glib                    # gsettings CLI
  nerd-fonts.jetbrains-mono
]
