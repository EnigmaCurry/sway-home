{ config, pkgs, lib, ... }:

{
  home.activation.rustup-default = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if command -v rustup >/dev/null 2>&1; then
      if ! rustup show active-toolchain >/dev/null 2>&1; then
        rustup default stable
      fi
    fi
  '';
}
