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
        craneLib = crane.lib."${system}".overrideToolchain rust.toolchain;
        buildInputs = with pkgs; [
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
        packages.bevy-game-bin = craneLib.buildPackage {
          name = "bevy-game-bin";
          src = craneLib.cleanCargoSource ./.;
          inherit buildInputs;
          inherit nativeBuildInputs;
        };

        packages.bevy-game-assets = pkgs.stdenv.mkDerivation {
          name = "bevy-game-assets";
          src = ./assets;
          phases = ["unpackPhase" "installPhase"];
          installPhase = ''
            mkdir -p $out
            cp -r $src $out/assets
          '';
        };

        packages.bevy-game = pkgs.stdenv.mkDerivation {
          name = "bevy-game";
          phases = ["installPhase"];
          installPhase = ''
            mkdir -p $out
            ln -s ${self.packages.${system}.bevy-game-assets}/assets $out/assets
            cp ${self.packages.${system}.bevy-game-bin}/bin/bevy-game $out/bevy-game
          '';
        };

        packages.bevy-game-wasm = let
          target = "wasm32-unknown-unknown";
          toolchainWasm = with fenix.packages.${system};
            combine [
              stable.rustc
              stable.cargo
              targets.${target}.stable.rust-std
            ];
          craneWasm = crane.lib.${system}.overrideToolchain toolchainWasm;
        in
          craneWasm.buildPackage {
            src = craneLib.cleanCargoSource ./.;
            CARGO_BUILD_TARGET = target;
            CARGO_PROFILE = "release";
            inherit nativeBuildInputs;
            doCheck = false;
          };

        packages.bevy-game-web = pkgs.stdenv.mkDerivation {
          name = "bevy-game-web";
          src = ./web;
          nativeBuildInputs = [
            pkgs.wasm-bindgen-cli
            pkgs.binaryen
          ];
          phases = ["unpackPhase" "installPhase"];
          installPhase = ''
            mkdir -p $out
            wasm-bindgen --out-dir $out --out-name bevy-game --target web ${self.packages.${system}.bevy-game-wasm}/bin/bevy-game.wasm
            mv $out/bevy-game_bg.wasm .
            wasm-opt -Oz -o $out/bevy-game_bg.wasm bevy-game_bg.wasm
            cp * $out/
            ln -s ${self.packages.${system}.bevy-game-assets}/assets $out/assets
          '';
        };

        packages.bevy-game-web-server = pkgs.writeShellScriptBin "bevy-game-web-server" ''
          ${pkgs.simple-http-server}/bin/simple-http-server -i -c=html,wasm,ttf,js -- ${self.packages.${system}.bevy-game-web}/
        '';

        defaultPackage = self.packages.${system}.bevy-game;

        apps.bevy-game = flake-utils.lib.mkApp {
          drv = self.packages.${system}.bevy-game;
          exePath = "/bevy-game";
        };

        apps.bevy-game-web-server = flake-utils.lib.mkApp {
          drv = self.packages.${system}.bevy-game-web-server;
          exePath = "/bin/bevy-game-web-server";
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
