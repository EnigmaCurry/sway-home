{ config, pkgs, lib, inputs, userName, ... }:

let
  myBashrc = inputs.sway-home + "/bashrc";
  myBashProfile = inputs.sway-home + "/bash_profile";

  swayConfigDir = inputs.sway-home + "/config";
  swayConfigTree = builtins.readDir swayConfigDir;

  swayBinDir = inputs.sway-home + "/bin";
  swayBinTree = builtins.readDir swayBinDir;

in {
  home.username = userName;
  home.homeDirectory = "/home/${userName}";
  home.stateVersion = "25.11";

  # Let home-manager manage itself when running standalone
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    includes = [
      { path = "~/.config/git/config.local"; }
    ];
  };

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

  # Symlink sway-home/bin/* into ~/bin/*
  home.file = lib.mapAttrs'
    (name: _:
      lib.nameValuePair "bin/${name}" {
        source = swayBinDir + "/${name}";
        executable = true;
      }
    )
    swayBinTree
    // {
      # Force overwrite existing bash files
      ".bashrc".force = true;
      ".bash_profile".force = true;
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
      swayConfigTree
    // {
      # git-prompt.sh for bash PS1 (fetched at build time, not runtime)
      "git-prompt.sh".source = inputs.git-prompt;
    };
}
