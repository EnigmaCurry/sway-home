{ config, pkgs, lib, inputs, ... }:

let
  myBashrc = inputs.sway-home + "/bashrc";
  myBashProfile = inputs.sway-home + "/bash_profile";

  swayConfigDir = inputs.sway-home + "/config";
  swayConfigTree = builtins.readDir swayConfigDir;

  swayBinDir = inputs.sway-home + "/bin";
  swayBinTree = builtins.readDir swayBinDir;

  scriptWizard = inputs.script-wizard.packages.${pkgs.stdenv.hostPlatform.system}.default;
in {
  # Identity (home.username/homeDirectory/stateVersion) and
  # programs.home-manager.enable live in baseline.nix, which is always on.
  # The shell/CLI content below is gated on my.home.dotfiles.enable; the GUI
  # package set is added separately under my.home.sway.enable at the end.
  config = lib.mkMerge [
   (lib.mkIf config.my.home.dotfiles.enable {
    # The CLI toolbox + the interactive script-wizard pod.
    home.packages =
      (import ./packages-dev.nix { inherit pkgs; })
      ++ (import ./packages-devops.nix { inherit pkgs; })
      ++ (import ./packages-net.nix { inherit pkgs; })
      ++ (import ./packages-shell.nix { inherit pkgs; })
      ++ (import ./packages-media.nix { inherit pkgs; })
      ++ [ scriptWizard ];

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
      "bin/git-vendor" = {
        source = inputs.blog-rymcg-tech + "/src/git/git_extensions.bb";
        executable = true;
      };
      "bin/git-deploy" = {
        source = inputs.blog-rymcg-tech + "/src/git/git_extensions.bb";
        executable = true;
      };
      "bin/git-deploy-key" = {
        source = inputs.blog-rymcg-tech + "/src/git/git_extensions.bb";
        executable = true;
      };
      "bin/git-remote-proto" = {
        source = inputs.blog-rymcg-tech + "/src/git/git_extensions.bb";
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
   })
   (lib.mkIf config.my.home.sway.enable {
     # GUI desktop packages (Wayland/Sway) -- added on top of the dotfiles.
     home.packages = import ./packages-gui.nix { inherit pkgs; };
   })
   (lib.mkIf (config.my.home.sway.enable && config.my.home.darkMode.enable) {
     # Dark mode preference for GTK4/libadwaita apps, including sandboxed
     # Flatpaks (Bazaar, etc.) that can only see the host theme via
     # xdg-desktop-portal-gtk's org.freedesktop.appearance interface.
     dconf.settings."org/gnome/desktop/interface" = {
       color-scheme = "prefer-dark";
       gtk-theme = "Adwaita-dark";
     };
   })
  ];
}
