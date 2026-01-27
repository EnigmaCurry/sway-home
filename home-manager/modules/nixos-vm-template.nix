{ config, pkgs, lib, inputs, ... }:

let
  nixosVmTemplateRepo = inputs.nixos-vm-template;
  envFile = "${config.xdg.configHome}/nixos-vm-template/env";
  defaultEnv = ''
    OUTPUT_DIR=$HOME/.local/share/nixos-vm-template
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
  '';
}
