///|
test "mcpx app paths: default files under ~/.config/mcpx" {
  let paths = mcpx_app_paths("/Users/alice")
  inspect(paths.config_dir, content="/Users/alice/.config/mcpx")
  inspect(
    paths.servers_config,
    content="/Users/alice/.config/mcpx/mcpServers.jsonc",
  )
  inspect(paths.env_file, content="/Users/alice/.config/mcpx/.env")
  inspect(
    paths.credentials_file,
    content="/Users/alice/.config/mcpx/credentials.json",
  )
  inspect(paths.cache_file, content="/Users/alice/.config/mcpx/cache.json")
}

///|
test "mcpx app paths: explicit config home wins over home" {
  let paths = mcpx_app_paths(
    "/Users/alice",
    config_home=Some("/tmp/xdg-config"),
  )
  inspect(paths.config_dir, content="/tmp/xdg-config/mcpx")
  inspect(paths.servers_config, content="/tmp/xdg-config/mcpx/mcpServers.jsonc")
  inspect(paths.env_file, content="/tmp/xdg-config/mcpx/.env")
  inspect(
    paths.credentials_file,
    content="/tmp/xdg-config/mcpx/credentials.json",
  )
  inspect(paths.cache_file, content="/tmp/xdg-config/mcpx/cache.json")
}

///|
test "mcpx app paths: servers config resolves json when jsonc is absent" {
  let config_home = "/tmp/mcpx-app-paths-json-config"
  let config_dir = config_home + "/mcpx"
  @fs.create_dir(config_home) catch {
    _ => ()
  }
  @fs.create_dir(config_dir) catch {
    _ => ()
  }
  @fs.remove_file(config_dir + "/mcpServers.jsonc") catch {
    _ => ()
  }
  @fs.remove_file(config_dir + "/mcpServers.json") catch {
    _ => ()
  }
  @fs.write_string_to_file(config_dir + "/mcpServers.json", "{}")
  inspect(
    mcpx_app_paths("/Users/alice", config_home=Some(config_home)).servers_config,
    content="/tmp/mcpx-app-paths-json-config/mcpx/mcpServers.json",
  )
}

///|
test "mcpx app paths: servers config prefers jsonc over json" {
  let config_home = "/tmp/mcpx-app-paths-jsonc-config"
  let config_dir = config_home + "/mcpx"
  @fs.create_dir(config_home) catch {
    _ => ()
  }
  @fs.create_dir(config_dir) catch {
    _ => ()
  }
  @fs.remove_file(config_dir + "/mcpServers.jsonc") catch {
    _ => ()
  }
  @fs.remove_file(config_dir + "/mcpServers.json") catch {
    _ => ()
  }
  @fs.write_string_to_file(config_dir + "/mcpServers.jsonc", "{}")
  @fs.write_string_to_file(config_dir + "/mcpServers.json", "{}")
  inspect(
    mcpx_app_paths("/Users/alice", config_home=Some(config_home)).servers_config,
    content="/tmp/mcpx-app-paths-jsonc-config/mcpx/mcpServers.jsonc",
  )
}

///|
test "mcpx app paths: empty or relative config home falls back to home" {
  inspect(
    mcpx_app_paths("/Users/alice", config_home=Some("")).config_dir,
    content="/Users/alice/.config/mcpx",
  )
  inspect(
    mcpx_app_paths("/Users/alice", config_home=Some("relative/config")).config_dir,
    content="/Users/alice/.config/mcpx",
  )
}
