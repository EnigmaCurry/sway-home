{ inputs, host, config, pkgs, ... }:

{
  #
  # This module is imported AFTER the shared /nixos/modules/configuration.nix,
  # so options you set here will typically win.
  #
  # Use lib.mkForce when you need to override a previous value that merges.

  # --- Enable Emacs/Home-Manager module on this host -------------------------
  home-manager.users.${host.userName}.imports = [
    (inputs.sway-home + "/nixos/modules/home/emacs.nix")
  ];

  # --- Allow incoming network ports ------
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];

  # --- Additional packages ----
  services.mullvad-vpn.enable = true;
  environment.systemPackages = with pkgs; [
    mullvad-browser mullvad-vpn btop
  ];

  # --- Enable CUPS to print documents ---
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # System programs and packages
  programs.firefox.enable = true;
  programs.sway.enable = true;
  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };
  programs.virt-manager.enable = true;
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  # Flatpak packages
  services.flatpak.enable = true;
  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.flatpak ];
    script = ''
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # # Or disable the firewall altogether.
  # networking.firewall.enable = false;
}
