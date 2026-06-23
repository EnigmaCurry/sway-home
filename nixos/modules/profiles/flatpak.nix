{ config, lib, pkgs, ... }:

# Flatpak with the Flathub remote pre-added. Enable with
# `my.profiles.flatpak.enable = true;`, then install apps with
# `flatpak install flathub <app>`.

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.my.profiles.flatpak;
in
{
  options.my.profiles.flatpak.enable =
    mkEnableOption "Flatpak (with the Flathub remote)";

  config = mkIf cfg.enable {
    services.flatpak.enable = true;

    # Flatpak requires XDG desktop portals (NixOS asserts this). The GTK
    # backend is the general-purpose one (file chooser, settings, etc.) and
    # works under sway; a desktop that ships its own portal just merges with
    # this one.
    xdg.portal.enable = true;
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

    # Register Flathub once at activation so `flatpak install flathub ...`
    # works out of the box.
    systemd.services.flatpak-repo = {
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.flatpak ];
      script = ''
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      '';
    };
  };
}
