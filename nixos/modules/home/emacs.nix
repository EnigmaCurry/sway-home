{ lib, inputs, host, ... }:

let
  cfg = host.emacs or { };
  enabled = cfg.enable or false;
  inputName = cfg.input or "emacs_enigmacurry";
in
{
  home.file.".emacs.d" = lib.mkIf enabled {
    source = inputs.${inputName};
    recursive = true;
  };
}
