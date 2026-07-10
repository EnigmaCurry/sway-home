{ lib, ... }:

# Prefer a dark UI for GTK4/libadwaita apps, including sandboxed Flatpaks
# (e.g. Bazaar) that only see the host theme via xdg-desktop-portal-gtk's
# org.freedesktop.appearance interface. Enable with
# `my.profiles.darkMode.enable = true;` (the installer writes this on by
# default; set false for light mode).
#
# This profile has no system-level config of its own -- it only drives the
# home-manager layer, mirrored into my.home.darkMode.enable by lib.mkHost
# (see flake.nix), which writes the dconf key when the sway profile is also
# enabled.

{
  options.my.profiles.darkMode.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    example = false;
    description = ''
      Whether to prefer a dark UI for GTK4/libadwaita apps (incl. sandboxed
      Flatpaks like Bazaar). Applied via dconf on the home-manager side;
      only takes effect on hosts that also enable the sway profile.
    '';
  };
}
