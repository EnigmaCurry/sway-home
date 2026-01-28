{ config, pkgs, lib, ... }:

let
  flatpakExists = builtins.pathExists "/run/current-system/sw/bin/flatpak"
    || builtins.pathExists "/usr/bin/flatpak"
    || builtins.pathExists "/var/lib/flatpak";
in
{
  services.flatpak = lib.mkIf flatpakExists {
    enable = true;

    remotes = [
      { name = "flathub"; location = "https://dl.flathub.org/repo/flathub.flatpakrepo"; }
    ];

    packages = [
      "flathub:io.github.kolunmi.Bazaar"
    ];

    update.onActivation = true;
  };
}
