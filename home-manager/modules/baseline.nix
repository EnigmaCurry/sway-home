{ lib, inputs, userName, ... }:

# Always-on home-manager baseline -- loaded on EVERY host (minimal server or
# sway desktop, NixOS or standalone). It owns the home-manager identity that
# must always be set, plus the `admin` alias a headless host needs to drive
# its ~/nixos repo. It also declares the `my.home.sway.enable` gate that the
# desktop content modules (home.nix, emacs.nix, firefox.nix, ...) switch on.

{
  options.my.home.sway.enable = lib.mkOption {
    type = lib.types.bool;
    # Defaults on so standalone home-manager (HOME_MANAGER.md, non-NixOS)
    # gets the full desktop. On NixOS, lib.mkHost overrides this from the
    # system's my.profiles.sway.enable.
    default = true;
    description = ''
      Whether to load the full sway desktop home-manager environment
      (dotfiles, packages, emacs, firefox, fluidsynth, ...). When false,
      only this baseline is active -- the headless-server essentials.
    '';
  };

  config = {
    home.username = userName;
    home.homeDirectory = "/home/${userName}";
    home.stateVersion = "26.05";

    # Let home-manager manage itself (esp. when running standalone).
    programs.home-manager.enable = true;

    # `admin` = run `just` in ~/nixos (this host's NixOS config repo, created
    # by `setup host`) with recipe + argument tab completion. On a sway host
    # the full bashrc (config/bash/alias.sh) also defines it; both paths
    # source the same _justfile_alias machinery, so defining it here too is
    # idempotent and gives headless servers the same alias.
    programs.bash = {
      enable = true;
      enableCompletion = true;
      initExtra = ''
        if command -v just >/dev/null; then
          source <(just --completions bash)
          source ${inputs.sway-home + "/config/bash/just-completion.sh"}
          if [ -f "$HOME/nixos/Justfile" ]; then
            _justfile_alias admin "$HOME/nixos/Justfile"
          fi
        fi
      '';
    };
  };
}
