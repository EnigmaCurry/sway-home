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
    emacs_enigmacurry = { url = "github:EnigmaCurry/emacs"; flake = false; };
  };

  outputs = inputs@{ self, ... }:
    let
      hosts = import ./hosts/hosts.nix;

      mkHost = host:
        let
          stableNixpkgs = inputs.${host.nixpkgsInput};
          unstableNixpkgs = inputs.nixpkgs_unstable;
          system = host.system or "x86_64-linux";

          unstablePkgs = unstableNixpkgs.legacyPackages.${system};

          hardwareModule = host.hardwareModule or null;

          hostUnstablePackages = host.unstablePackages or [];
          hostExtraPackages = host.extraPackages or [];
          extraSystemModules = host.extraSystemModules or [];

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

                ({ ... }: { _module.args.host = host; })
                ({ ... }: { my.unstablePkgs = hostUnstablePackages; })

                ({ pkgs, ... }:
                  let
                    toPkgs = names:
                      map (name:
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

                # Base system config (shared by all hosts)
                ./modules/configuration.nix
              ]
              # Host-specific override/extra modules (Option A)
              ++ extraSystemModules
              ++ [
                { networking.hostName = host.hostName; }

                (import ./modules/user.nix { inherit userName; })

                inputs.home-manager_25_11.nixosModules.home-manager
                ({ ... }: {
                  home-manager = {
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    backupFileExtension = "backup";
                    extraSpecialArgs = { inherit inputs userName host; };

                    users.${userName} = { pkgs, ... }: {
                      imports = [
                        ./modules/home/home.nix
                      ];
                      home.packages = import ./modules/home/packages.nix { inherit pkgs; };
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
