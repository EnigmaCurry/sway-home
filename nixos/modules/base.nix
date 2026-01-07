{ config, pkgs, ... }:

{
  # Opt-in for "experimental" flakes support (defacto standard, but possibly unstable)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  # To configure NetworkManager, manually place .nmconnection files in /etc/NetworkManager
  networking.networkmanager.enable = true;

  # Login manager
  services.greetd.enable = true;
  services.greetd.settings = {
    default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --user-menu --cmd sway";
      user = "greeter";
    };
  };

  environment.systemPackages = with pkgs; [
    curl
    tuigreet
    git
    ripgrep
    jq
    just
    # Need lxsession only for lxpolkit to be able to access libvirt / virt-manager
    lxsession
  ];
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}

