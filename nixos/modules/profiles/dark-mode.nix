{ config, lib, ... }:

# Prefer a dark UI for GTK apps, including sandboxed Flatpaks (e.g. Bazaar)
# that only see the host theme via xdg-desktop-portal-gtk's
# org.freedesktop.appearance interface. Enable with
# `my.profiles.darkMode.enable = true;` (the installer writes this on by
# default; set false for light mode).
#
# GTK4/libadwaita side: driven by home-manager, mirrored into
# my.home.darkMode.enable by lib.mkHost (see flake.nix), which writes the
# color-scheme dconf key when the sway profile is also enabled.
#
# GTK3 side: sets GTK_THEME=Adwaita:dark in the system session environment
# so GTK3 apps launched by sway (e.g. Thunar) render dark. sway itself is
# started by greetd and doesn't source .bashrc, so relying on the shell's
# theme.sh only covers apps launched from a terminal.

let
  cfg = config.my.profiles.darkMode;
in
{
  options.my.profiles.darkMode.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    example = false;
    description = ''
      Whether to prefer a dark UI for GTK apps (incl. sandboxed Flatpaks
      like Bazaar). Sets GTK_THEME for the system session and drives
      home-manager to write the dconf color-scheme key; only takes effect
      on hosts that also enable the sway profile.
    '';
  };

  config = lib.mkIf cfg.enable {
    environment.sessionVariables.GTK_THEME = "Adwaita:dark";
  };
}
