{ config, pkgs, ... }:

{
  # Core system config shared by ALL hosts. The Sway desktop bits live in
  # the sway profile module (nixos/modules/profiles/sway.nix), gated by
  # my.profiles.sway.enable.

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

  # Bash completion, system-wide (generally welcome on a headless box; the
  # per-user interactive shells get their own completion via home-manager).
  programs.bash.completion.enable = true;

  # Stub dynamic linker so generic-Linux binaries can run on NixOS. Needed
  # because babashka pods (e.g. the ones auto-downloaded by `vm`/`pve` from
  # nixos-vm-template when loaded by qualified name+version) ship prebuilt
  # ELF binaries expecting /lib64/ld-linux-x86-64.so.2.
  # See: https://nix.dev/permalink/stub-ld
  programs.nix-ld.enable = true;

  # The `admin` alias (run `just` in ~/nixos with full recipe + argument
  # tab completion) is set up by home-manager on every host now --
  # home-manager/modules/baseline.nix wires it directly, and on a sway host
  # config/bash/alias.sh defines it too; both source the same _justfile_alias
  # machinery. It is no longer wired here at the system level via /etc/bashrc.

  # This value determines the NixOS release from which the default
  # settings for stateful data were taken. Leave it at the release version
  # of the first install of this system.
  system.stateVersion = "26.05"; # Did you read the comment?
}
