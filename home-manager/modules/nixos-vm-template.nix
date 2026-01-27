{ config, pkgs, lib, inputs, ... }:

let
  nixosVmTemplateRepo = inputs.nixos-vm-template;
  configDir = "${config.xdg.configHome}/nixos-vm-template";
  envFile = "${configDir}/env";
  libvirtDir = "${configDir}/libvirt";
  defaultEnv = ''
    OUTPUT_DIR=$HOME/.local/share/nixos-vm-template
    MACHINES_DIR=$HOME/.config/nixos-vm-template/machines
    LIBVIRT_DIR=$HOME/.config/nixos-vm-template/libvirt
  '';
in
{
  home.file."nixos-vm-template".source = nixosVmTemplateRepo;

  home.activation.nixos-vm-template-env = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f "${envFile}" ]; then
      mkdir -p "$(dirname "${envFile}")"
      cat > "${envFile}" << 'EOF'
${defaultEnv}
EOF
    fi
    mkdir -p "${libvirtDir}"
    ln -sf "${nixosVmTemplateRepo}/libvirt/template.xml" "${libvirtDir}/template.xml"
  '';
}
