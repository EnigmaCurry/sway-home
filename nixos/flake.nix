{
  description = "NixOS with Sway-Home";

  inputs = {
    nixpkgs_25_11.url = "nixpkgs/nixos-25.11";
    nixpkgs_unstable.url = "nixpkgs/nixos-unstable";

    home-manager_25_11 = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs_25_11";
    };

    sway-home = { url = "path:.."; flake = false; };
  };

  outputs = inputs@{ self, ... }:
    let
      hosts = import ./modules/hosts.nix;

      mkHost = host:
        let
          stableNixpkgs = inputs.${host.nixpkgsInput};
          unstableNixpkgs = inputs.nixpkgs_unstable;
          system = host.system or "x86_64-linux";

          unstablePkgs = unstableNixpkgs.legacyPackages.${system};

          hardwareModule = host.hardwareModule or null;
          hostModule = host.hostModule or null;
          hostUnstablePackages = host.unstablePackages or [];
          hostExtraPackages = host.extraPackages or [];
          userName = host.userName;
        in
          stableNixpkgs.lib.nixosSystem {
            inherit system;

            specialArgs = {
              inherit inputs unstablePkgs;
            };

            modules =
              (stableNixpkgs.lib.optional (hardwareModule != null) hardwareModule)
              ++ (stableNixpkgs.lib.optional (hostModule != null) hostModule)
              ++ [
                ./modules/unstable-overlay.nix

                # Drive the overlay from hosts.nix
                ({ ... }: { my.unstablePkgs = hostUnstablePackages; })

                ./modules/configuration.nix
                { networking.hostName = host.hostName; }
                (import ./modules/user.nix { inherit userName; })

                inputs.home-manager_25_11.nixosModules.home-manager
                ({ ... }: {
                  home-manager = {
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    backupFileExtension = "backup";

                    users.${userName} = { ... }: {
                      _module.args = {
                        inherit inputs userName;
                        unstablePackages = hostUnstablePackages;
                        extraPackages = hostExtraPackages;
                      };
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
