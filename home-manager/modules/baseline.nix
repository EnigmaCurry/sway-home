{ lib, inputs, userName, ... }:

# Always-on home-manager baseline -- loaded on EVERY host (minimal server or
# sway desktop, NixOS or standalone). It owns the home-manager identity that
# must always be set, plus the `admin` alias a headless host needs to drive
# its ~/nixos repo. It also declares the two gates the content modules switch
# on: `my.home.dotfiles.enable` (shell/CLI: bashrc, ~/bin, ~/.config, emacs,
# CLI tools) and `my.home.sway.enable` (the GUI desktop adds on top).

{
  options.my.home.dotfiles.enable = lib.mkOption {
    type = lib.types.bool;
    # Defaults on for standalone home-manager (HOME_MANAGER.md, non-NixOS).
    # On NixOS, lib.mkHost overrides this from my.profiles.dotfiles.enable
    # (and sway implies it).
    default = true;
    description = ''
      Whether to load the shell/CLI home-manager environment: bashrc, the
      ~/bin scripts, the ~/.config dotfiles, git config, emacs, the
      nixos-vm-template env, and the CLI package toolbox. No GUI.
    '';
  };

  options.my.home.sway.enable = lib.mkOption {
    type = lib.types.bool;
    # Defaults on so standalone home-manager (HOME_MANAGER.md, non-NixOS)
    # gets the full desktop. On NixOS, lib.mkHost overrides this from the
    # system's my.profiles.sway.enable.
    default = true;
    description = ''
      Whether to load the GUI desktop home-manager content on top of the
      dotfiles: firefox, fluidsynth, and the Wayland/Sway package set.
    '';
  };

  options.my.home.flatpak.enable = lib.mkOption {
    type = lib.types.bool;
    # Off by default -- flatpak is a NixOS-level opt-in. On NixOS, lib.mkHost
    # overrides this from my.profiles.flatpak.enable. Standalone home-manager
    # users can flip it on manually if they have flatpak on their host.
    default = false;
    description = ''
      Whether to declare the user's flatpak package set via nix-flatpak
      (adds the flathub remote and installs Bazaar).
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
