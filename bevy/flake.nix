{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    fenix,
    crane,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages."${system}";
        rust = fenix.packages.${system}.stable;
        crane-lib = crane.lib."${system}".overrideToolchain rust.toolchain;
        buildInputs = with pkgs; [
          libxkbcommon
          alsaLib
          udev
          xorg.libXcursor
          xorg.libXi
          xorg.libXrandr
          libxkbcommon
          vulkan-loader
          wayland
        ];
        nativeBuildInputs = with pkgs; [
          mold
          pkg-config
        ];
      in {
        packages.bevy-game-bin = crane-lib.buildPackage {
          name = "bevy-game-bin";
          src = crane-lib.cleanCargoSource ./.;
          inherit buildInputs;
          inherit nativeBuildInputs;
        };
        packages.bevy-game = pkgs.stdenv.mkDerivation {
          name = "bevy-game";
          src = ./assets;
          phases = ["unpackPhase" "installPhase"];
          installPhase = ''
            mkdir -p $out
            cp ${self.packages.${system}.bevy-game-bin}/bin/bevy-game $out/bevy-game
            cp -r $src $out/assets
          '';
        };

        defaultPackage = self.packages.${system}.bevy-game;

        apps.bevy-game = flake-utils.lib.mkApp {
          drv = self.packages.${system}.bevy-game;
          exePath = "/bevy-game";
        };
        defaultApp = self.apps.${system}.bevy-game;

        checks = {
          pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              alejandra.enable = true;
              statix.enable = true;
              rustfmt.enable = true;
              clippy = {
                enable = false;
                entry = let
                  rust-clippy = rust-clippy.withComponents ["clippy"];
                in
                  pkgs.lib.mkForce "${rust-clippy}/bin/cargo-clippy clippy";
              };
            };
          };
        };

        devShell = pkgs.mkShell {
          shellHook = ''
            export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${pkgs.lib.makeLibraryPath buildInputs}"
            ${self.checks.${system}.pre-commit-check.shellHook}
          '';
          inherit buildInputs;
          nativeBuildInputs =
            [
              (rust.withComponents ["cargo" "rustc" "rust-src" "rustfmt" "clippy"])
            ]
            ++ nativeBuildInputs;
        };
      }
    );
}
