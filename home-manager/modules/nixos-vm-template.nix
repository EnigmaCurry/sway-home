{ config, pkgs, lib, inputs, ... }:

let
  nixosVmTemplateRepo = inputs.nixos-vm-template;
in
{
  home.file."nixos-vm-template" = {
    source = nixosVmTemplateRepo;
    recursive = true;
  };
}
