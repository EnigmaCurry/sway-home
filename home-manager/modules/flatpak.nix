{ config, pkgs, lib, ... }:

let
  flatpakExists = builtins.pathExists "/run/current-system/sw/bin/flatpak"
    || builtins.pathExists "/usr/bin/flatpak"
    || builtins.pathExists "/var/lib/flatpak";
in
{
  # Gated on sway (desktop) AND on flatpak actually being present on the host.
  services.flatpak = lib.mkIf (config.my.home.sway.enable && flatpakExists) {
    enable = true;

    remotes = [
      { name = "flathub"; location = "https://dl.flathub.org/repo/flathub.flatpakrepo"; }
    ];

    packages = [
      "io.github.kolunmi.Bazaar"
    ];

    update.onActivation = true;
  };
}
