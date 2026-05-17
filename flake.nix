{
  description = "mcpx - native MCP CLI and portable MCP client runtime";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    moonbit-overlay.url = "github:moonbit-community/moonbit-overlay/v0.9.2+bbe2b338f+81d40e3";
    moon-registry = {
      url = "git+https://mooncakes.io/git/index";
      flake = false;
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      flake = {
        overlays.default = final: prev:
          let
            moonAttrs = inputs.moonbit-overlay.overlays.default final prev;
          in
          {
            mcpx = final.callPackage ./package.nix {
              moonPlatform = final.moonPlatform or moonAttrs.moonPlatform;
              moonRegistryIndex = inputs.moon-registry;
            };
          };
      };

      perSystem = { system, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ inputs.moonbit-overlay.overlays.default ];
          };

          mcpx = pkgs.callPackage ./package.nix {
            moonRegistryIndex = inputs.moon-registry;
          };

          moonHome = pkgs.moonPlatform.bundleWithRegistry {
            cachedRegistry = pkgs.moonPlatform.buildCachedRegistry {
              moonModJson = ./moon.mod.json;
              registryIndexSrc = inputs.moon-registry;
            };
          };
        in
        {
          packages = {
            default = mcpx;
            inherit mcpx;
          };

          apps = {
            default = {
              type = "app";
              program = "${mcpx}/bin/mcpx";
            };
            mcpx = {
              type = "app";
              program = "${mcpx}/bin/mcpx";
            };
          };

          devShells.default = pkgs.mkShellNoCC {
            packages = [
              moonHome
              pkgs.bash
              pkgs.curl
              pkgs.git
            ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.openssl
            ];
            env = {
              MOON_HOME = "${moonHome}";
            } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
              LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.openssl ];
            };
          };
        };
    };
}
