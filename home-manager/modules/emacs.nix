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

  # Wrapper function that auto-detects terminal mode when no display available
  programs.bash.initExtra = ''
    emacs() {
      if [[ -z "$DISPLAY" && -z "$WAYLAND_DISPLAY" ]]; then
        command emacs -nw "$@"
      else
        command emacs "$@"
      fi
    }
  '';
}
