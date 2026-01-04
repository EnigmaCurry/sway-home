{
  description = "NixOS with Sway-Home";

  inputs = {
    nixpkgs_25_11.url = "nixpkgs/nixos-25.11";
    nixpkgs_unstable.url = "nixpkgs/nixos-unstable";

    home-manager_25_11 = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs_25_11";
    };

    # optional; keep if you want it around
    home-manager_unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };

    sway-home = {
      url = "path:..";
      flake = false;
    };
  };

  outputs = inputs@{ self, ... }:
    let
      hosts = import ./modules/hosts.nix;

      mkHost = host:
        let
          nixpkgs = inputs.${host.nixpkgsInput};
          home-manager = inputs.${host.homeManagerInput};

          # recommended: define per-host system in hosts.nix
          system = host.system or "x86_64-linux";

          # unstable packages for the same system
          pkgsUnstable = inputs.nixpkgs_unstable.legacyPackages.${system};

          hardwareModule = host.hardwareModule or null;
          hostModule = host.hostModule or null;
          userName = host.userName;
        in
          nixpkgs.lib.nixosSystem {
            inherit system;

            # make these available to ALL NixOS modules
            specialArgs = {
              inherit inputs pkgsUnstable;
            };

            modules =
              (nixpkgs.lib.optional (hardwareModule != null) hardwareModule)
              ++ (nixpkgs.lib.optional (hostModule != null) hostModule)
              ++ [
                # provides option: my.unstablePackages = [ "emacs" ... ];
                ./modules/unstable-overlay.nix

                ./modules/configuration.nix
                { networking.hostName = host.hostName; }
                (import ./modules/user.nix { inherit userName; })

                home-manager.nixosModules.home-manager
                ({ ... }: {
                  home-manager = {
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    backupFileExtension = "backup";

                    users.${userName} = { ... }: {
                      # force args for home.nix
                      _module.args = { inherit inputs userName; };
                      imports = [ ./modules/home.nix ];
                    };
                  };
                })
              ];
          };
    in
    {
      nixosConfigurations =
        inputs.nixpkgs_25_11.lib.mapAttrs (_: mkHost) hosts;
    };
}
