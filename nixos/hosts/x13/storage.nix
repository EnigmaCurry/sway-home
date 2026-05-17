{ lib, ... }:

{
  # Wrapper module so you can add host-specific storage tweaks
  # without editing the generated hardware.nix.
  imports = [ ./hardware.nix ];

  swapDevices = lib.mkForce [ { device = "/dev/mapper/luks-2d7ae1cc-e2d1-4efc-a0ca-18edf5894726"; }
    ];
}
