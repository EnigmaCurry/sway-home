{
  x1 = {
    hostName = "x1";
    userName = "ryan";
    system = "x86_64-linux";
    nixpkgsInput = "nixpkgs_25_11";
    homeManagerInput = "home-manager_25_11";
    hardwareModule = ../hosts/x1/hardware.nix;
    hostModule = ../hosts/x1/host.nix;
  };
}
