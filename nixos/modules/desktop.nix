{ pkgs, ... }:

{
  # Sway desktop -- included only for the "sway" profile (see lib.mkHost).
  # The user's sway/waybar/etc. config comes from home-manager (all.nix);
  # this module provides the system-level login manager and desktop deps.

  # Sway compositor + system session plumbing (polkit, dbus, SUID
  # wrapper, session vars). The user's sway/waybar/etc. config still
  # comes from home-manager (all.nix); this just installs the binary
  # and wires up the login session.
  programs.sway.enable = true;

  # Login manager -> sway
  services.greetd.enable = true;
  services.greetd.settings = {
    default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --user-menu --cmd sway";
      user = "greeter";
    };
  };

  environment.systemPackages = with pkgs; [
    tuigreet
    # lxsession only for lxpolkit (libvirt / virt-manager access)
    lxsession
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];
}
