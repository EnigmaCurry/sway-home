# Import all home-manager modules (used by both standalone and NixOS flakes).
#
# baseline.nix is always active; the rest are the sway desktop content, each
# gated internally by `my.home.sway.enable` (declared in baseline.nix). They
# are always imported but inert on a minimal host -- this keeps a
# sway<->minimal flip declarative (home-manager prunes the dotfiles it stops
# managing instead of orphaning them).
{ inputs, ... }:
{
  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
    ./baseline.nix
    ./home.nix
    ./emacs.nix
    ./nixos-vm-template.nix
    ./flatpak.nix
    ./fluidsynth.nix
    ./firefox.nix
  ];
}
