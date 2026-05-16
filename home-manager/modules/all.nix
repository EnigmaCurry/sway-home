# Import all home-manager modules (used by both standalone and NixOS flakes)
{ inputs, ... }:
{
  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
    ./home.nix
    ./emacs.nix
    ./nixos-vm-template.nix
    ./rust.nix
    ./flatpak.nix
    ./fluidsynth.nix
    ./firefox.nix
  ];
}
