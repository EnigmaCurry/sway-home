{ config, pkgs, inputs, userName, ... }:

let
  myBashrc = inputs.sway-home + "/bashrc";
  myBashProfile = inputs.sway-home + "/bash_profile";
in
{
  home.username = userName;
  home.homeDirectory = "/home/${userName}";
  home.stateVersion = "25.11";

  programs.git.enable = true;
  home.packages = import ./user-packages.nix { inherit pkgs; };

  programs.bash = {
    enable = true;
    # ~/.bashrc imports sway-home bashrc:
    bashrcExtra = ''
      source "${myBashrc}"
    '';
    # ~/.bash_profile import sway-home bash_profile:
    profileExtra = ''
      source "${myBashProfile}"
    '';
    # shellAliases = {
    #   btw = "echo i use nixos, btw";
    # };
  };
}
