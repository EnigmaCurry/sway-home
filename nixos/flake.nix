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
          nixpkgs = inputs.${host.nixpkgsInput};
          system = host.system or "x86_64-linux";

          # This is what unstable-overlay.nix expects:
          pkgsUnstable = inputs.nixpkgs_unstable.legacyPackages.${system};

          hardwareModule = host.hardwareModule or null;
          hostModule = host.hostModule or null;

          extraPackages = host.extraPackages or [];
          unstablePackages = host.unstablePackages or [];
          userName = host.userName;
        in
          nixpkgs.lib.nixosSystem {
            inherit system;

            specialArgs = {
              inherit inputs pkgsUnstable;
            };

            modules =
              (nixpkgs.lib.optional (hardwareModule != null) hardwareModule)
              ++ (nixpkgs.lib.optional (hostModule != null) hostModule)
              ++ [
                ./modules/unstable-overlay.nix

                # Drive the overlay from hosts.nix
                ({ ... }: { my.unstablePackages = unstablePackages; })

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
                        extraPackages = extraPackages;
                        unstablePackages = unstablePackages;
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
