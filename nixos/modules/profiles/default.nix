{ ... }:

# Composable feature profiles. Every module here is ALWAYS imported but does
# nothing until its `my.profiles.<name>.enable` flag is set (in a host's
# config.nix). Each module owns the complete recipe for its subsystem.
#
# This is the additive counterpart to the base `profile` arg (minimal | sway)
# in flake.nix: that one is a mutually-exclusive "size" that drives the
# home-manager layer and must stay a static arg; these are orthogonal
# add-ons toggled per host.

{
  imports = [
    ./libvirt.nix
    ./podman.nix
    ./flatpak.nix
    ./sound.nix
  ];
}
