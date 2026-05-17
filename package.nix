{
  lib,
  moonPlatform,
  moonRegistryIndex,
}:

moonPlatform.buildMoonPackage {
  name = "mcpx";
  src = ./.;
  moonModJson = ./moon.mod.json;
  inherit moonRegistryIndex;
  moonTarget = "native";
  moonFlags = [ "cli" ];

  # Package builds should produce the native CLI only. The native test suite
  # exercises chmod, daemon, and socket behavior that is covered in CI but is
  # not reliable inside every Nix sandbox.
  doCheck = false;

  installPhase = ''
    mkdir -p "$out/bin"
    install -Dm755 "$TMP/_build/native/release/build/cli/cli.exe" "$out/bin/mcpx"
  '';

  meta = {
    description = "Native CLI for MCP servers";
    homepage = "https://github.com/yata-one/mcpx";
    license = lib.licenses.mit;
    mainProgram = "mcpx";
  };
}
