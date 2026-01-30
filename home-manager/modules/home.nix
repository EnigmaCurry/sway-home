{ config, pkgs, lib, inputs, userName, ... }:

let
  myBashrc = inputs.sway-home + "/bashrc";
  myBashProfile = inputs.sway-home + "/bash_profile";

  swayConfigDir = inputs.sway-home + "/config";
  swayConfigTree = builtins.readDir swayConfigDir;

  swayBinDir = inputs.sway-home + "/bin";
  swayBinTree = builtins.readDir swayBinDir;

in {
  home.username = userName;
  home.homeDirectory = "/home/${userName}";
  home.stateVersion = "25.11";

  # Let home-manager manage itself when running standalone
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    includes = [
      { path = "~/.config/git/config.local"; }
    ];
  };

  # Create editable git config.local if it doesn't exist
  home.activation.createGitConfigLocal = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -f ~/.config/git/config.local ]; then
      mkdir -p ~/.config/git
      cat > ~/.config/git/config.local << 'EOF'
[init]
    defaultBranch = master
EOF
    fi
  '';

  programs.bash = {
    enable = true;
    bashrcExtra = ''
      # Source Nix profile (for non-NixOS systems)
      # This runs for all interactive shells, not just login shells
      if [ -e '/etc/profile.d/nix-daemon.sh' ]; then
        . '/etc/profile.d/nix-daemon.sh'
      elif [ -e '/etc/profile.d/nix.sh' ]; then
        . '/etc/profile.d/nix.sh'
      fi

      source "${myBashrc}"
    '';
    profileExtra = ''
      source "${myBashProfile}"
    '';
  };

  # Symlink sway-home/bin/* into ~/bin/*
  home.file = lib.mapAttrs'
    (name: _:
      lib.nameValuePair "bin/${name}" {
        source = swayBinDir + "/${name}";
        executable = true;
      }
    )
    swayBinTree
    // {
      # Force overwrite existing bash files
      ".bashrc".force = true;
      ".bash_profile".force = true;
      # Scripts from external repos (blog.rymcg.tech)
      "bin/traefik_local_auth_proxy.sh" = {
        source = inputs.blog-rymcg-tech + "/src/traefik/traefik_local_auth_proxy.sh";
        executable = true;
      };
      "bin/rclone_sync.sh" = {
        source = inputs.blog-rymcg-tech + "/src/rclone/rclone_sync.sh";
        executable = true;
      };
      "bin/rclone_webdav.sh" = {
        source = inputs.blog-rymcg-tech + "/src/rclone/rclone_webdav.sh";
        executable = true;
      };
      "bin/ssh_expose.sh" = {
        source = inputs.blog-rymcg-tech + "/src/ssh/ssh_expose.sh";
        executable = true;
      };
      "bin/ssh_remote_xdg_open.sh" = {
        source = inputs.blog-rymcg-tech + "/src/ssh/ssh_remote_xdg_open.sh";
        executable = true;
      };
      "bin/wireguard_p2p.sh" = {
        source = inputs.blog-rymcg-tech + "/src/wireguard/wireguard_p2p.sh";
        executable = true;
      };
      "bin/netwatch.sh" = {
        source = inputs.blog-rymcg-tech + "/src/netwatch/netwatch.sh";
        executable = true;
      };
      "bin/proxmox_container.sh" = {
        source = inputs.blog-rymcg-tech + "/src/proxmox/proxmox_container.sh";
        executable = true;
      };
      "bin/proxmox_firewall.sh" = {
        source = inputs.blog-rymcg-tech + "/src/proxmox/proxmox_firewall.sh";
        executable = true;
      };
      "bin/proxmox_kvm.sh" = {
        source = inputs.blog-rymcg-tech + "/src/proxmox/proxmox_kvm.sh";
        executable = true;
      };
      "bin/proxmox_nat.sh" = {
        source = inputs.blog-rymcg-tech + "/src/proxmox/proxmox_nat.sh";
        executable = true;
      };
      "bin/restic_backup.sh" = {
        source = inputs.blog-rymcg-tech + "/src/systemd/restic_backup.sh";
        executable = true;
      };
      "bin/nix_build_iso.sh" = {
        source = inputs.blog-rymcg-tech + "/src/nix/nix_build_iso.sh";
        executable = true;
      };
      "bin/git-vendor" = {
        source = inputs.blog-rymcg-tech + "/src/git/git_vendor.sh";
        executable = true;
      };
      "bin/git-clone-deploy" = {
        source = inputs.blog-rymcg-tech + "/src/git/git_clone_deploy.sh";
        executable = true;
      };
    };

  # Symlink sway-home/config/* into ~/.config/*
  xdg.enable = true;
  xdg.configFile =
    lib.mapAttrs'
      (name: kind:
        lib.nameValuePair name (
          if kind == "directory" then
            { source = swayConfigDir + "/${name}"; recursive = true; }
          else
            { source = swayConfigDir + "/${name}"; }
        )
      )
      swayConfigTree
    // {
      # git-prompt.sh for bash PS1 (fetched at build time, not runtime)
      "git-prompt.sh".source = inputs.git-prompt;
    };
}
