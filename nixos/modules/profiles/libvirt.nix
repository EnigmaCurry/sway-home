{ config, lib, pkgs, host, ... }:

# libvirt / KVM virtualization. Drives the `vm` command (nixos-vm-template),
# virt-manager, and virsh. Enabling this owns the WHOLE recipe: the daemon,
# a KVM-capable qemu with swtpm (emulated TPM 2.0 for UEFI guests), and the
# user's libvirtd group membership -- so `vm list` can reach the socket after
# a re-login. Enable with `my.profiles.libvirt.enable = true;`.

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.my.profiles.libvirt;
in
{
  options.my.profiles.libvirt.enable =
    mkEnableOption "libvirt/KVM virtualization (the `vm` command, virt-manager)";

  config = mkIf cfg.enable {
    programs.virt-manager.enable = true;

    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
      };
    };

    # Group membership is the other half of the recipe -- without it virsh
    # gets a permission error instead of reaching the socket. Merges with the
    # base groups from user.nix. Takes effect on the next login.
    users.users.${host.userName}.extraGroups = [ "libvirtd" ];
  };
}
