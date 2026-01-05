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
              ++ [
                ./modules/unstable-overlay.nix
                ./modules/host-locale.nix
                ({ ... }: {
                  my.host = {
                    locale = host.locale or {};
                    xkb = host.xkb or {};
                  };
                })

                ({ ... }: { my.unstablePkgs = hostUnstablePackages; })

                ({ pkgs, ... }:
                  let
                    toPkgs = names: map (name:
                      if builtins.hasAttr name pkgs
                      then builtins.getAttr name pkgs
                      else throw "hosts.nix packages: pkgs has no attribute '${name}'"
                    ) names;
                  in
                    {
                      environment.systemPackages =
                        toPkgs (hostExtraPackages ++ hostUnstablePackages);
                    }
                )
                ./modules/configuration.nix
                { networking.hostName = host.hostName; }
                (import ./modules/user.nix { inherit userName; })
                inputs.home-manager_25_11.nixosModules.home-manager
                ({ ... }: {
                  home-manager = {
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    backupFileExtension = "backup";
                    extraSpecialArgs = { inherit inputs userName; };
                    users.${userName} = { pkgs, ... }: {
                      imports = [ ./modules/home.nix ];
                      home.packages = import ./modules/user-packages.nix { inherit pkgs; };
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
