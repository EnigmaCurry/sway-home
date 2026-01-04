{ lib, config, pkgsUnstable, ... }:

let
  inherit (lib) mkOption types;
in
{
  options.my.unstablePackages = mkOption {
    type = types.listOf types.str;
    default = [];
    description = "Package attribute names to take from nixpkgs_unstable (e.g. \"emacs\").";
  };

  config.nixpkgs.overlays = [
    (final: prev:
      lib.genAttrs config.my.unstablePackages (name:
        if builtins.hasAttr name pkgsUnstable
        then builtins.getAttr name pkgsUnstable
        else throw "my.unstablePackages: pkgsUnstable has no attribute '${name}'"
      )
    )
  ];
}
