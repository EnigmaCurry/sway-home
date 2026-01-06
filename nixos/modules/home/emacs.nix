{ config, pkgs, lib, inputs, ... }:

let
  emacsRepo = inputs.emacs_enigmacurry;
in
{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-pgtk;
  };

  home.file.".emacs.d" = {
    source = emacsRepo;
    recursive = true;
  };

}
