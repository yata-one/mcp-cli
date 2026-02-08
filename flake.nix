{
  description = "mcp-cli (MoonBit native) - a lightweight CLI for MCP servers";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.writeShellApplication {
            name = "mcp-cli";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.curl
              pkgs.gawk
              pkgs.gnutar
              pkgs.gzip
              pkgs.gnused
            ];
            text = ''
              set -euo pipefail

              repo="yata-one/mcp-cli"
              version="''${MCP_CLI_VERSION:-}"
              if [ -z "$version" ]; then
                version="$(
                  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
                  | sed -n 's/.*"tag_name": "\\([^"]*\\)".*/\\1/p'
                )"
              fi

              case "$(uname -s)-$(uname -m)" in
                Linux-x86_64) suffix="linux-x64" ;;
                Darwin-arm64) suffix="macos-arm64" ;;
                *)
                  echo "unsupported platform: $(uname -s) $(uname -m)" >&2
                  exit 1
                  ;;
              esac

              asset="mcp-cli-$version-$suffix.tar.gz"
              url="https://github.com/$repo/releases/download/$version/$asset"

              cache_base="''${XDG_CACHE_HOME:-$HOME/.cache}/mcp-cli"
              cache_dir="$cache_base/$version/$suffix"
              bin="$cache_dir/mcp-cli"

              if [ ! -x "$bin" ]; then
                mkdir -p "$cache_dir"

                tmp="$(mktemp -d)"
                trap 'rm -rf "$tmp"' EXIT

                archive="$tmp/$asset"
                curl -fsSL -o "$archive" "$url"

                sums_url="https://github.com/$repo/releases/download/$version/SHA256SUMS"
                if curl -fsSL -o "$tmp/SHA256SUMS" "$sums_url"; then
                  expected="$(awk -v asset="$asset" '$2==asset {print $1}' "$tmp/SHA256SUMS")"
                  if [ -n "$expected" ]; then
                    actual="$(sha256sum "$archive" | awk '{print $1}')"
                    if [ "$expected" != "$actual" ]; then
                      echo "checksum mismatch for $asset" >&2
                      exit 1
                    fi
                  fi
                fi

                tar -xzf "$archive" -C "$tmp"
                install -m 0755 "$tmp/mcp-cli" "$bin"
              fi

              exec "$bin" "$@"
            '';
          };
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/mcp-cli";
        };
      });
    };
}
