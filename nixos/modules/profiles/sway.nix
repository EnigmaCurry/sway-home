{ config, lib, pkgs, host, ... }:

# Sway desktop -- the system-level half (login manager, compositor, session
# plumbing, fonts). The user's sway/waybar/etc. dotfiles come from
# home-manager, gated by the same flag via osConfig (see
# home-manager/modules/baseline.nix). Enable with
# `my.profiles.sway.enable = true;`.
#
# Back-compat: the option default tracks the legacy `profile = "sway"` arg
# that older per-host flakes still pass to lib.mkHost, so they keep their
# desktop without editing config.nix. New hosts set the flag explicitly (the
# installer writes it), which overrides the default. The legacy arg is
# otherwise unused and can be dropped from a host's flake.nix.

let
  inherit (lib) mkIf;
  cfg = config.my.profiles.sway;
in
{
  options.my.profiles.sway.enable = lib.mkOption {
    type = lib.types.bool;
    default = (host.profile or "minimal") == "sway";
    example = true;
    description = "Whether to enable the Sway desktop environment.";
  };

  config = mkIf cfg.enable {
    # Sway compositor + system session plumbing (polkit, dbus, SUID wrapper,
    # session vars). This just installs the binary and wires up the login
    # session; the user config still comes from home-manager.
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
  };
}
