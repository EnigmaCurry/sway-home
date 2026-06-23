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
