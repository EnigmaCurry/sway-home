{ config, pkgs, inputs, ... }:

{
  # Core system config shared by ALL hosts (every profile). The Sway
  # desktop bits live in desktop.nix, included only for the "sway"
  # profile (see lib.mkHost).

  # Opt-in for flakes (defacto standard).
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Symlink /bin/bash for scripts with #!/bin/bash shebangs
  system.activationScripts.binbash = ''
    ln -sfn ${pkgs.bash}/bin/bash /bin/bash
  '';

  # Boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  # To configure NetworkManager, place .nmconnection files in /etc/NetworkManager
  networking.networkmanager.enable = true;

  # SSH, key-only -- so headless machines stay reachable after reboot.
  # Per-host authorized keys are set in the host repo's config.nix.
  services.openssh.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "prohibit-password";
  };

  # Git, system-wide. The host's config.nix adds a scoped
  # `safe.directory` for its own flake repo, so `sudo nixos-rebuild
  # --flake ~/nixos` (running as root) can read the user-owned repo
  # without git's "dubious ownership" error.
  programs.git.enable = true;

  environment.systemPackages = with pkgs; [
    curl
    ripgrep
    jq
    just
  ];

  # Bash completion, system-wide (the 'admin' helper below relies on it,
  # and it's generally welcome on a headless box).
  programs.bash.completion.enable = true;

  # 'admin' = run `just` in this host's config repo (~/nixos, created by
  # `setup host`) with full recipe + argument tab completion. Defined here
  # at the system level so it works on EVERY profile: the "sway" profile
  # also gets it through home-manager's ~/.bashrc (config/bash/alias.sh),
  # but "minimal" has no home-manager, so this is what reaches it (via
  # /etc/bashrc, sourced by SSH login shells). Both paths source the same
  # _justfile_alias machinery from the repo, so behaviour is identical.
  programs.bash.interactiveShellInit = ''
    if command -v just >/dev/null; then
      source <(just --completions bash)
      source ${inputs.sway-home + "/config/bash/just-completion.sh"}
      if [ -f "$HOME/nixos/Justfile" ]; then
        _justfile_alias admin "$HOME/nixos/Justfile"
      fi
    fi
  '';

  # This value determines the NixOS release from which the default
  # settings for stateful data were taken. Leave it at the release version
  # of the first install of this system.
  system.stateVersion = "26.05"; # Did you read the comment?
}
