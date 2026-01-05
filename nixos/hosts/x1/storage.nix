{ ... }:
{
  imports = [ ./hardware.nix ];

  ## Swap is optional, comment this out if you don't need it.
  ## Make sure this disk uuid matches your real encrypted swap device:
  boot.initrd.luks.devices."luks-870208a0-81da-419c-9a4b-50b18b2d0710".device =
    "/dev/disk/by-uuid/870208a0-81da-419c-9a4b-50b18b2d0710";

}
