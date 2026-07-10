{ config, pkgs, lib, ... }:

{
  # Gated on my.home.flatpak.enable (mirrored from my.profiles.flatpak.enable
  # by lib.mkHost). The NixOS profile guarantees flatpak is installed
  # system-wide, so the home-manager side can just declare the package set.
  services.flatpak = lib.mkIf config.my.home.flatpak.enable {
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
