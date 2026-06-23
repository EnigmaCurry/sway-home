{ config, pkgs, lib, inputs, ... }:

let
  nixosVmTemplateRepo = inputs.nixos-vm-template;
  configDir = "${config.xdg.configHome}/nixos-vm-template";
  envFile = "${configDir}/env";
  pveEnvFile = "${configDir}/pve.env";
  libvirtDir = "${configDir}/libvirt";
  # MACHINES_DIR is intentionally not set: it defaults to
  # <config>/nixos-vm-template/machines/<backend>/<host>, which keeps each
  # backend's machines separate automatically. LIBVIRT_DIR points at the
  # writable copy of the template XMLs symlinked below.
  defaultEnv = ''
    OUTPUT_DIR=$HOME/.local/share/nixos-vm-template
    LIBVIRT_DIR=$HOME/.config/nixos-vm-template/libvirt
  '';
  # Env file for the `pve` (proxmox) alias. Machines land in
  # machines/proxmox/<host>, parallel to machines/libvirt/<host>. Set PVE_HOST
  # (an ~/.ssh/config host) before using it.
  defaultPveEnv = ''
    BACKEND=proxmox
    OUTPUT_DIR=$HOME/.local/share/nixos-vm-template
    #PVE_HOST=pve
    #PVE_STORAGE=local
    #PVE_BRIDGE=vmbr0
  '';
in
{
  config = lib.mkIf config.my.home.sway.enable {
  home.file."nixos-vm-template".source = nixosVmTemplateRepo;

  home.activation.nixos-vm-template-env = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f "${envFile}" ]; then
      mkdir -p "$(dirname "${envFile}")"
      cat > "${envFile}" << 'EOF'
${defaultEnv}
EOF
    fi
    if [ ! -f "${pveEnvFile}" ]; then
      mkdir -p "$(dirname "${pveEnvFile}")"
      cat > "${pveEnvFile}" << 'EOF'
${defaultPveEnv}
EOF
    fi
    mkdir -p "${libvirtDir}"
    ln -sf "${nixosVmTemplateRepo}/libvirt/template.xml" "${libvirtDir}/template.xml"
    ln -sf "${nixosVmTemplateRepo}/libvirt/template-mutable.xml" "${libvirtDir}/template-mutable.xml"
  '';
  };
}
