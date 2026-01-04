{ userName }:
{ pkgs, ... }:
{
  users.users.${userName} = {
    isNormalUser = true;
    description = userName;
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.bashInteractive;
  };
}
