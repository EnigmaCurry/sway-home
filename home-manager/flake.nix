{
  description = "Home Manager configuration for sway-home";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs_unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    sway-home = { url = "path:.."; flake = false; };
    emacs_enigmacurry = { url = "github:EnigmaCurry/emacs"; flake = false; };
    nixos-vm-template = { url = "github:EnigmaCurry/nixos-vm-template"; flake = false; };
    git-prompt = { url = "https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh"; flake = false; };
    blog-rymcg-tech = { url = "github:EnigmaCurry/blog.rymcg.tech"; flake = false; };
    script-wizard.url = "github:EnigmaCurry/script-wizard";
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
          };
          # all.nix pulls in baseline + the sway desktop content. home.nix
          # provides home.packages, gated by my.home.sway.enable which
          # defaults true here (standalone).
          modules = [ ./modules/all.nix ] ++ extraModules;
        };
    in
    {
      # Default home configuration - uses $USER from environment
      # Usage: just hm-switch
      # Or: home-manager switch --flake .#default --impure -b backup
      homeConfigurations.default = mkHomeConfiguration {
        userName = currentUser;
        system = defaultSystem;
      };

      # Export modules for NixOS flake to import
      homeModules = {
        home = ./modules/home.nix;
        packages-dev = ./modules/packages-dev.nix;
        packages-devops = ./modules/packages-devops.nix;
        packages-net = ./modules/packages-net.nix;
        packages-shell = ./modules/packages-shell.nix;
        packages-media = ./modules/packages-media.nix;
        packages-gui = ./modules/packages-gui.nix;
        packages-input = ./modules/packages-input.nix;
        emacs = ./modules/emacs.nix;
        nixos-vm-template = ./modules/nixos-vm-template.nix;
        flatpak = ./modules/flatpak.nix;
        fluidsynth = ./modules/fluidsynth.nix;
        firefox = ./modules/firefox.nix;
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
