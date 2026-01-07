{ lib, ... }:

{
  # Wrapper module so you can add host-specific storage tweaks
  # without editing the generated hardware.nix.
  imports = [ ./hardware.nix ];

  swapDevices = lib.mkForce [ { device = "/dev/mapper/luks-870208a0-81da-419c-9a4b-50b18b2d0710"; }
    ];
}
