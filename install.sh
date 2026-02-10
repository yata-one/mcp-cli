#!/usr/bin/env bash
set -euo pipefail

repo="yata-one/mcp-cli"
bin_dir="${MCP_CLI_BIN_DIR:-${HOME}/.local/bin}"
version=""

usage() {
  cat <<'EOF'
Usage:
  install.sh [--version <tag>] [--bin-dir <dir>]

Examples:
  curl -fsSL https://raw.githubusercontent.com/yata-one/mcp-cli/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/yata-one/mcp-cli/main/install.sh | bash -s -- --version v0.1.0
  curl -fsSL https://raw.githubusercontent.com/yata-one/mcp-cli/main/install.sh | bash -s -- --bin-dir /usr/local/bin
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -v|--version)
      version="${2:-}"
      shift 2
      ;;
    -b|--bin-dir)
      bin_dir="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "${version}" ]; then
  version="$(
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
    | grep -m1 '"tag_name":' \
    | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/'
  )"
fi

if [ -z "${version}" ]; then
  echo "failed to detect latest release tag; retry with --version <tag>" >&2
  exit 1
fi

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) suffix="linux-x64" ;;
  Darwin-arm64) suffix="macos-arm64" ;;
  *)
    echo "unsupported platform: $(uname -s) $(uname -m)" >&2
    exit 1
    ;;
esac

asset="mcp-cli-${version}-${suffix}.tar.gz"
url="https://github.com/${repo}/releases/download/${version}/${asset}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

archive="${tmp}/${asset}"
curl -fsSL -o "$archive" "$url"

if command -v sha256sum >/dev/null 2>&1; then
  expected="$(
    curl -fsSL "https://github.com/${repo}/releases/download/${version}/SHA256SUMS" \
    | awk -v asset="$asset" '$2==asset {print $1}'
  )"
  if [ -n "${expected}" ]; then
    actual="$(sha256sum "$archive" | awk '{print $1}')"
    if [ "$expected" != "$actual" ]; then
      echo "checksum mismatch for $asset" >&2
      exit 1
    fi
  fi
elif command -v shasum >/dev/null 2>&1; then
  expected="$(
    curl -fsSL "https://github.com/${repo}/releases/download/${version}/SHA256SUMS" \
    | awk -v asset="$asset" '$2==asset {print $1}'
  )"
  if [ -n "${expected}" ]; then
    actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
    if [ "$expected" != "$actual" ]; then
      echo "checksum mismatch for $asset" >&2
      exit 1
    fi
  fi
fi

tar -xzf "$archive" -C "$tmp"

mkdir -p "$bin_dir"
install -m 0755 "$tmp/mcp-cli" "$bin_dir/mcp-cli"

echo "installed: $bin_dir/mcp-cli"
