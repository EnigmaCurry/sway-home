{ lib, pkgs, ... }:

{
  # Host-specific overrides go here.
  #
  # This module is imported AFTER the shared ./modules/configuration.nix,
  # so options you set here will typically win.
  #
  # Use lib.mkForce when you need to override a previous value that merges.
  #
  # Examples:
  #
  # services.openssh.enable = lib.mkForce false;
  #
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
  #
  # environment.systemPackages = with pkgs; [
  #   tcpdump
  # ];
}
