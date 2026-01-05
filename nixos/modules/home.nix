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

  programs.git.enable = true;

  programs.bash = {
    enable = true;
    bashrcExtra = ''
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
