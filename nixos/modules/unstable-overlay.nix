{ lib, config, unstablePkgs, ... }:

let
  inherit (lib) mkOption types;
in
{
  options.my.unstablePkgs = mkOption {
    type = types.listOf types.str;
    default = [];
    description = "Package attribute names to take from nixpkgs_unstable (e.g. \"emacs\").";
  };

  config.nixpkgs.overlays = [
    (final: prev:
      lib.genAttrs config.my.unstablePkgs (name:
        if builtins.hasAttr name unstablePkgs
        then builtins.getAttr name unstablePkgs
        else throw "my.unstablePkgs: unstablePkgs has no attribute '${name}'"
      )
    )
  ];
}
