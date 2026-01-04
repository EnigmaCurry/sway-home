{
  description = "NixOS with Sway-Home";

  inputs = {
    nixpkgs_25_11.url = "nixpkgs/nixos-25.11";
    nixpkgs_unstable.url = "nixpkgs/nixos-unstable";

    home-manager_25_11 = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs_25_11";
    };

    home-manager_unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };

    sway-home = { url = "path:.."; flake = false; };
  };

  outputs = inputs@{ self, ... }:
    let
      hosts = import ./modules/hosts.nix;

      mkHost = host:
        let
          nixpkgs = inputs.${host.nixpkgsInput};
          home-manager = inputs.${host.homeManagerInput};
        in
          nixpkgs.lib.nixosSystem {
            modules =
              (nixpkgs.lib.optional (host.hardwareModule or null != null) host.hardwareModule)
              ++ [
                ./modules/configuration.nix
                { networking.hostName = host.hostName; }
                (import ./modules/user.nix { userName = host.userName; })

                home-manager.nixosModules.home-manager
                ({ ... }: {
                  home-manager.users.${host.userName} = { ... }: {
                    _module.args = { inherit inputs; userName = host.userName; };
                    imports = [ ./modules/home.nix ];
                  };
                })
              ];
          };
    in
      {
        # Load hosts via stable mapAttrs function loaded from nixpkgs_25_11:
        nixosConfigurations = inputs.nixpkgs_25_11.lib.mapAttrs (_: mkHost) hosts;
      };
}
