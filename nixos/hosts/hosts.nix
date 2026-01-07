{
  x1 = {
    hostName = "x1";
    userName = "ryan";
    system = "x86_64-linux";
    nixpkgsInput = "nixpkgs_25_11";
    ## Point the hardwareModule to the installer generated (pristine) hardware.nix,
    ## or point to storage.nix if you need to postprocess it with your own config:
    ## (storage.nix is used to configure the swap device uuid).
    hardwareModule = ../hosts/x1/storage.nix;
    extraSystemModules = [
      ./x1/config.nix
    ];
    unstablePackages = [ "just" "quickemu" ];
    extraPackages = [ "minicom" ];
    locale = {
      timeZone = "America/Denver";
      defaultLocale = "en_US.UTF-8";
    };
    xkb = {
      layout = "us";
      variant = "";
      options = "ctrl:nocaps";
      consoleUseXkbConfig = true;
    };
  };

  foo = {
    hostName = "foo";
    userName = "ryan";
    system = "x86_64-linux";
    nixpkgsInput = "nixpkgs_25_11";
    # Use storage.nix so you can override storage bits (swap, luks, etc.)
    # while still importing the generated hardware.nix.
    hardwareModule = ../hosts/foo/storage.nix;
    # Host-specific system overrides (imported after base configuration.nix)
    extraSystemModules = [
      ../hosts/foo/config.nix
    ];
    extraPackages = [ ];
    unstablePackages = [ ];
    # Per-host schema consumed by modules/host-locale.nix
    locale = {
      timeZone = "America/Denver";
      defaultLocale = "en_US.UTF-8";
      # extraLocaleSettings = {
      #   LC_TIME = "en_US.UTF-8";
      # };
    };
    xkb = {
      layout = "us";
      variant = "";
      options = "ctrl:nocaps";
      consoleUseXkbConfig = true;
    };
  };
}
