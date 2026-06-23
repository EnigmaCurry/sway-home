{ config, lib, ... }:

# Podman containers (Docker-compatible). Enable with
# `my.profiles.podman.enable = true;`.

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.my.profiles.podman;
in
{
  options.my.profiles.podman.enable =
    mkEnableOption "Podman containers (Docker-compatible)";

  config = mkIf cfg.enable {
    # Podman is rootless by default -- no group membership required.
    virtualisation.podman = {
      enable = true;
      # Container DNS so containers can resolve each other by name.
      defaultNetwork.settings.dns_enabled = true;
    };
  };
}
