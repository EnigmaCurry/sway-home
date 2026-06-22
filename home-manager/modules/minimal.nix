# Home config for the "minimal" profile.
#
# home-manager is present on every profile (see lib.mkHost) so that a
# `sway` -> `minimal` downgrade is fully declarative: home-manager removes
# the sway dotfiles it no longer manages instead of orphaning them. On the
# minimal profile it manages only the essentials a headless server needs --
# chiefly the `admin` alias for driving this host's ~/nixos config repo.
#
# The full desktop environment lives in all.nix, loaded by the "sway"
# profile instead.
{ inputs, userName, osConfig, ... }:
{
  home.username = userName;
  home.homeDirectory = "/home/${userName}";

  # Track the system's stateVersion (set once in base.nix) rather than
  # hardcoding another copy here. This module only ever runs inside the
  # NixOS home-manager module, so osConfig is always available.
  home.stateVersion = osConfig.system.stateVersion;

  programs.home-manager.enable = true;

  # `admin` = run `just` in ~/nixos (this host's NixOS config repo, created
  # by `setup host`) with full recipe + argument tab completion. On the
  # "sway" profile this comes from config/bash/alias.sh via the full bashrc;
  # here we wire it directly so headless servers get the same alias. Both
  # paths source the same _justfile_alias machinery from the repo.
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
}
