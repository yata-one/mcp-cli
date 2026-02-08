# Release Plan (GitHub Releases + sh installer + Nix flake + mise GitHub backend)

このプロジェクトの配布は **GitHub Releases を唯一の配布元**とし、そこに置いた成果物を:

- `curl | sh` で入れる（`scripts/install.sh`）
- `nix run github:yata-one/mcp-cli` で入れる（`flake.nix`）
- `mise use -g github:yata-one/mcp-cli` で入れる（mise の GitHub backend）

で参照する。

## Non-goals

- Homebrew formula は提供しない
- OS パッケージ（apt/rpm 等）は提供しない

## Versioning

- tag は `vX.Y.Z`（例: `v0.1.0`）
- `mcp-cli --version` の表示は release 前に更新する（現状は `cli/main.mbt` に固定文字列）

## Release assets（命名規約）

mise の GitHub backend が自動選択しやすいように、asset 名に **OS/arch を明示**する。

推奨:

- `mcp-cli-v{{version}}-linux-x64.tar.gz`
- `mcp-cli-v{{version}}-linux-arm64.tar.gz`
- `mcp-cli-v{{version}}-macos-x64.tar.gz`
- `mcp-cli-v{{version}}-macos-arm64.tar.gz`

同梱物:

- `mcp-cli`（実行ファイル、root に置く）
- `LICENSE`（任意）
- `README.md`（任意）

追加で `SHA256SUMS` を Release assets に含める（全 tar.gz の sha256）。

> MoonBit の成果物は `_build/native/release/build/cli/cli.exe` のため、パッケージング時に `mcp-cli` へリネームして tar に入れる。

## GitHub Actions（リリース自動化の方針）

tag push（`v*`）で:

1. `moon check --target native --deny-warn --fmt`
2. `moon test --target native`
3. `bash scripts/e2e.sh`
4. `moon build --target native --release cli`
5. `mcp-cli` に rename して `tar.gz` を作成
6. `SHA256SUMS` を生成
7. GitHub Release を作成し、assets を upload

### CI matrix（例）

最初は現実的な範囲でよい（例: `linux-x64`, `macos-arm64`）。

- linux-x64: `ubuntu-latest`
- macos-arm64: `macos-latest`
- macos-x64: `macos-13`（必要なら）
- linux-arm64: 必要になったら追加（self-hosted / cross / qemu 等を検討）

## sh installer（`scripts/install.sh` の方針）

### ユーザー体験

```sh
curl -fsSL https://raw.githubusercontent.com/yata-one/mcp-cli/main/scripts/install.sh | sh
```

（任意）バージョン指定:

```sh
curl -fsSL https://raw.githubusercontent.com/yata-one/mcp-cli/main/scripts/install.sh | sh -s -- --version v0.1.0
```

### 仕様

- OS/arch を `uname -s` / `uname -m` から判定し asset 名へマップ
  - OS: `Linux` → `linux`, `Darwin` → `macos`
  - arch: `x86_64|amd64` → `x64`, `arm64|aarch64` → `arm64`
- `--version` 未指定時は GitHub API `releases/latest` から tag を取得（`vX.Y.Z`）
- `SHA256SUMS` を使って検証（`sha256sum` が無ければ `shasum -a 256`）
- インストール先:
  - デフォルト: `~/.local/bin`
  - `--dir <path>`（または `MCP_CLI_INSTALL_DIR`）で変更可
- 依存: `curl`, `tar`（+ checksum コマンド）

## Nix（flake の方針）

### ユーザー体験

```sh
nix run github:yata-one/mcp-cli
```

### 方針（MVP）

- `flake.nix` は **GitHub Releases の tar.gz を fetch** して `mcp-cli` を `$out/bin` に配置する
  - MoonBit toolchain を Nix 内に持ち込まない（実装が小さい）
- `packages.default` と `apps.default` を提供する
- 各 system ごとに `url` と `sha256` を固定（リリースごとに更新）

> 将来的に「Nix でソースからビルド」したくなった場合は、MoonBit toolchain の扱い（nixpkgs 依存 or vendoring）を別途検討する。

## mise（GitHub backend の方針）

### ユーザー体験

```sh
mise use -g github:yata-one/mcp-cli@0.1.0
```

### 方針

- 上記の asset 命名規約（`linux/macos` + `x64/arm64` + `tar.gz`）を守り、mise 側の自動選択に乗る
- 必要なら `.mise.toml` で `github` backend を明示できるが、基本は不要

