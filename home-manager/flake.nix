{
  description = "Home Manager configuration for sway-home";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs_unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    sway-home = { url = "path:.."; flake = false; };
    emacs_enigmacurry = { url = "github:EnigmaCurry/emacs"; flake = false; };
    nixos-vm-template = { url = "github:EnigmaCurry/nixos-vm-template"; flake = false; };
    git-prompt = { url = "https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh"; flake = false; };
    blog-rymcg-tech = { url = "github:EnigmaCurry/blog.rymcg.tech"; flake = false; };
    script-wizard.url = "github:EnigmaCurry/script-wizard";
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs_unstable, home-manager, ... }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      defaultSystem = "x86_64-linux";

      # Get current user from $USER env var (requires --impure flag)
      currentUser = builtins.getEnv "USER";

      mkHomeConfiguration = { userName, system ? defaultSystem, extraModules ? [] }:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          unstablePkgs = nixpkgs_unstable.legacyPackages.${system};
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit inputs userName unstablePkgs;
            script-wizard = inputs.script-wizard.packages.${system}.default;
          };
          modules = [
            inputs.nix-flatpak.homeManagerModules.nix-flatpak
            ./modules/home.nix
            ({ pkgs, script-wizard, ... }: {
              home.packages = (import ./modules/packages.nix { inherit pkgs; }) ++ [ script-wizard ];
            })
          ] ++ extraModules;
        };
    in
    {
      # Default home configuration - uses $USER from environment
      # Usage: just hm-switch
      # Or: home-manager switch --flake .#default --impure -b backup
      homeConfigurations.default = mkHomeConfiguration {
        userName = currentUser;
        system = defaultSystem;
        extraModules = [ ./modules/emacs.nix ./modules/nixos-vm-template.nix ./modules/rust.nix ./modules/flatpak.nix ];
      };

      # Export modules for NixOS flake to import
      homeModules = {
        home = ./modules/home.nix;
        packages = ./modules/packages.nix;
        emacs = ./modules/emacs.nix;
        nixos-vm-template = ./modules/nixos-vm-template.nix;
        rust = ./modules/rust.nix;
        flatpak = ./modules/flatpak.nix;
      };

      # Helper function for creating configurations
      lib = {
        inherit mkHomeConfiguration;
      };

      # Development shell with home-manager available
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            buildInputs = [ home-manager.packages.${system}.default ];
          };
        }
      );
    };
}
