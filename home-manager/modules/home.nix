{ config, pkgs, lib, inputs, userName, ... }:

let
  myBashrc = inputs.sway-home + "/bashrc";
  myBashProfile = inputs.sway-home + "/bash_profile";

  swayConfigDir = inputs.sway-home + "/config";
  swayConfigTree = builtins.readDir swayConfigDir;

in {
  home.username = userName;
  home.homeDirectory = "/home/${userName}";
  home.stateVersion = "25.11";

  # Let home-manager manage itself when running standalone
  programs.home-manager.enable = true;

  programs.git.enable = true;

  programs.bash = {
    enable = true;
    bashrcExtra = ''
      # Source Nix profile (for non-NixOS systems)
      # This runs for all interactive shells, not just login shells
      if [ -e '/etc/profile.d/nix-daemon.sh' ]; then
        . '/etc/profile.d/nix-daemon.sh'
      elif [ -e '/etc/profile.d/nix.sh' ]; then
        . '/etc/profile.d/nix.sh'
      fi

      source "${myBashrc}"
    '';
    profileExtra = ''
      source "${myBashProfile}"
    '';
  };

  # Symlink sway-home/config/* into ~/.config/*
  xdg.enable = true;
  xdg.configFile =
    lib.mapAttrs'
      (name: kind:
        lib.nameValuePair name (
          if kind == "directory" then
            { source = swayConfigDir + "/${name}"; recursive = true; }
          else
            { source = swayConfigDir + "/${name}"; }
        )
      )
      swayConfigTree;
}
