{
  description = "Headless NixOS installer ISO (SSH + serial + WiFi + tools)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
    in {
      nixosConfigurations.installer = lib.nixosSystem {
        inherit system;
        modules = [
          # Minimal installer ISO base
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"

          ({ config, pkgs, lib, ... }:
            let
              # ---- Customize these ----
              sshPubKey = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNds......fksdf=";

              wifiSsid = "YOUR_WIFI_SSID";
              wifiPsk  = "YOUR_WIFI_PASSWORD";
              nmConnName = "bootstrap-wifi";
              webhookUrl = "";
              # -------------------------
            in
            {
              networking.hostName = "nixos-installer";

              # DHCP is usually already on in the installer, but explicit is fine
              networking.useDHCP = lib.mkDefault true;

              # --- SSH ---
              services.openssh.enable = true;
              services.openssh.settings = {
                PasswordAuthentication = false;
                KbdInteractiveAuthentication = false;
                PermitRootLogin = "prohibit-password"; # keys only
              };

              users.users.root.openssh.authorizedKeys.keys = [ sshPubKey ];
              # Alternative: use the "nixos" user instead of root
              # users.users.nixos.openssh.authorizedKeys.keys = [ sshPubKey ];

              # --- Serial console ---
              # Kernel output on serial helps a lot on headless servers.
              boot.kernelParams = [ "console=ttyS0,115200" ];

              # Start serial getty at boot (equivalent to starting it manually)
              systemd.services."serial-getty@ttyS0" = {
                enable = true;
                wantedBy = [ "getty.target" ];
              };

              # --- NetworkManager + pre-seeded WiFi ---
              networking.networkmanager.enable = true;

              # NetworkManager keyfile profiles must be root-owned and mode 0600.
              environment.etc."NetworkManager/system-connections/${nmConnName}.nmconnection" = {
                mode = "0600";
                text = ''
                  [connection]
                  id=${nmConnName}
                  type=wifi
                  autoconnect=true

                  [wifi]
                  mode=infrastructure
                  ssid=${wifiSsid}

                  [wifi-security]
                  key-mgmt=wpa-psk
                  psk=${wifiPsk}

                  [ipv4]
                  method=auto

                  [ipv6]
                  method=auto
                '';
              };

              # --- Installer toolbox ---
              environment.systemPackages = with pkgs; [
                # network / remote
                git curl wget openssh rsync
                # disks / filesystems
                parted gptfdisk e2fsprogs btrfs-progs xfsprogs dosfstools
                cryptsetup lvm2 mdadm
                # debugging / comfort
                tmux neovim nano htop
                pciutils usbutils
                iproute2 iputils dnsutils
              ];

              # --- Webhook fires once network is up ---
              # Put the script into the ISO at /etc/webhook-notify.sh
              environment.etc."webhook-notify.sh" = {
                mode = "0755";
                ## relative path to nixos/build-iso/foo/../webhook-notify.sh
                source = ../webhook-notify.sh;
              };

              systemd.services.webhook-notify = {
                description = "POST hostname + local IP to webhook once network is up";
                wantedBy = [ "multi-user.target" ];
                after = [ "network-online.target" ];
                wants = [ "network-online.target" ];

                # Provide runtime deps for the script
                path = with pkgs; [ bash curl iproute2 gawk coreutils ];

                serviceConfig = {
                  Type = "oneshot";
                  TimeoutStartSec = "2min";
                  StandardOutput = "journal+console";
                  StandardError = "journal+console";

                  # Pass the webhook URL to the script
                  Environment = [ "WEBHOOK_URL=${webhookUrl}" ];
                };

                script = ''
                      exec /etc/webhook-notify.sh
                '';
              };
            })
        ];
      };

      packages.${system}.iso =
        self.nixosConfigurations.installer.config.system.build.isoImage;
    };
}
