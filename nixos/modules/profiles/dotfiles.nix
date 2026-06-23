{ lib, ... }:

# The shell / CLI home-manager environment WITHOUT the GUI desktop: bashrc,
# bash_profile, ~/bin scripts, the ~/.config dotfiles, git config, emacs, the
# nixos-vm-template env, and the CLI package toolbox (packages.nix). Enable
# with `my.profiles.dotfiles.enable = true;`.
#
# This profile has no system-level config of its own -- it only drives the
# home-manager layer, mirrored into my.home.dotfiles.enable by lib.mkHost (see
# flake.nix). The `sway` profile implies it (a desktop wants the shell env
# too), so you only need this one on a headless server.

{
  options.my.profiles.dotfiles.enable =
    lib.mkEnableOption "the sway-home shell/CLI home-manager environment (dotfiles, emacs, CLI tools) without the GUI desktop";
}
