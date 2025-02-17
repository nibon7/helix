{
  description = "A post-modern text editor.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    nixCargoIntegration = {
      url = "github:yusdacra/nix-cargo-integration";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rustOverlay.follows = "rust-overlay";
    };
  };

  outputs = inputs@{ self, nixCargoIntegration, ... }:
    nixCargoIntegration.lib.makeOutputs {
      root = ./.;
      buildPlatform = "crate2nix";
      renameOutputs = { "helix-term" = "helix"; };
      # Set default app to hx (binary is from helix-term release build)
      # Set default package to helix-term release build
      defaultOutputs = { app = "hx"; package = "helix"; };
      overrides = {
        crateOverrides = common: _: rec {
          # link languages and theme toml files since helix-view expects them
          helix-view = _: { preConfigure = "ln -s ${common.root}/{languages.toml,theme.toml,base16_theme.toml} .."; };
          helix-syntax = prev: {
            src =
              let
                pkgs = common.pkgs;
                helix = pkgs.fetchgit {
                  url = "https://github.com/helix-editor/helix.git";
                  rev = "a8fd33ac012a79069ef1409503a2edcf3a585153";
                  fetchSubmodules = true;
                  sha256 = "sha256-5AtOC55ttWT+7RYMboaFxpGZML51ix93wAkYJTt+8JI=";
                };
              in
              pkgs.runCommand prev.src.name { } ''
                mkdir -p $out
                ln -s ${prev.src}/* $out
                ln -sf ${helix}/helix-syntax/languages $out
              '';
            preConfigure = "mkdir -p ../runtime/grammars";
            postInstall = "cp -r ../runtime $out/runtime";
          };
          helix-term = prev:
            let
              inherit (common) pkgs lib;
              helixSyntax = lib.buildCrate {
                root = self;
                memberName = "helix-syntax";
                defaultCrateOverrides = {
                  helix-syntax = helix-syntax;
                };
                release = false;
              };
              runtimeDir = pkgs.runCommand "helix-runtime" { } ''
                mkdir -p $out
                ln -s ${common.root}/runtime/* $out
                ln -sf ${helixSyntax}/runtime/grammars $out
              '';
            in
            {
              # link languages and theme toml files since helix-term expects them (for tests)
              preConfigure = "ln -s ${common.root}/{languages.toml,theme.toml,base16_theme.toml} ..";
              buildInputs = (prev.buildInputs or [ ]) ++ [ common.cCompiler.cc.lib ];
              nativeBuildInputs = [ pkgs.makeWrapper ];
              postFixup = ''
                if [ -f "$out/bin/hx" ]; then
                  wrapProgram "$out/bin/hx" --set HELIX_RUNTIME "${runtimeDir}"
                fi
              '';
            };
        };
        shell = common: prev: {
          packages = prev.packages ++ (with common.pkgs; [ lld_13 lldb cargo-tarpaulin ]);
          env = prev.env ++ [
            { name = "HELIX_RUNTIME"; eval = "$PWD/runtime"; }
            { name = "RUST_BACKTRACE"; value = "1"; }
            { name = "RUSTFLAGS"; value = "-C link-arg=-fuse-ld=lld -C target-cpu=native"; }
          ];
        };
      };
    };
}
