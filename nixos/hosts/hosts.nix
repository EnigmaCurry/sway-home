{
  x1 = {
    hostName = "x1";
    userName = "ryan";
    system = "x86_64-linux";
    nixpkgsInput = "nixpkgs_25_11";
    # Use storage.nix so you can override storage bits (swap, luks, etc.)
    # while still importing the generated hardware.nix.
    hardwareModule = ../hosts/x1/storage.nix;
    # Host-specific system overrides (imported after base configuration.nix)
    extraSystemModules = [
      ../hosts/x1/config.nix
    ];
    extraPackages = [ ];
    unstablePackages = [ ];
    # Per-host schema consumed by modules/host-locale.nix
    locale = {
      timeZone = "America/Denver";
      defaultLocale = "en_US.UTF-8";
      xkb = {
        layout = "us";
        variant = "";
        options = "ctrl:nocaps";
        consoleUseXkbConfig = true;
      };
    };
  };
}
