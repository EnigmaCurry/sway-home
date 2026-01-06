{ host, ... }:

{
  # Host-specific overrides go here.
  #
  # This module is imported AFTER the shared ./modules/configuration.nix,
  # so options you set here will typically win.
  #
  # Use lib.mkForce when you need to override a previous value that merges.

  # --- Enable Emacs/Home-Manager module on this host -------------------------
  home-manager.users.${host.userName}.imports = [
    ../../modules/home/emacs.nix
  ];

  # --- Allow incoming network ports ------
  # networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
