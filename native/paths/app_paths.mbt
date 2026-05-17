///|
pub struct McpxAppPaths {
  config_dir : String
  servers_config : String
  env_file : String
  credentials_file : String
  cache_file : String
}

///|
pub fn mcpx_app_paths(
  home : String,
  config_home? : String? = None,
) -> McpxAppPaths {
  let base = match config_home {
    Some(path) if is_absolute_path(path) => path
    _ => join_path(home, ".config")
  }
  let config_dir = join_path(base, "mcpx")
  let servers_config_jsonc = join_path(config_dir, "mcpServers.jsonc")
  let servers_config_json = join_path(config_dir, "mcpServers.json")
  {
    config_dir,
    servers_config: resolve_existing_or_default(
      [servers_config_jsonc, servers_config_json],
      servers_config_jsonc,
    ),
    env_file: join_path(config_dir, ".env"),
    credentials_file: join_path(config_dir, "credentials.json"),
    cache_file: join_path(config_dir, "cache.json"),
  }
}

///|
fn resolve_existing_or_default(
  candidates : Array[String],
  default : String,
) -> String {
  for path in candidates {
    if @fs.path_exists(path) {
      return path
    }
  }
  default
}

///|
fn is_absolute_path(path : String) -> Bool {
  path.has_prefix("/") || has_windows_drive_prefix(path)
}

///|
fn has_windows_drive_prefix(path : String) -> Bool {
  let chars = path.to_array()
  match (chars.get(0), chars.get(1), chars.get(2)) {
    (Some(drive), Some(':'), Some('\\'))
    | (Some(drive), Some(':'), Some('/')) => is_ascii_letter(drive)
    _ => false
  }
}

///|
fn is_ascii_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn join_path(base : String, child : String) -> String {
  if base.has_suffix("/") || base.has_suffix("\\") {
    base + child
  } else {
    base + "/" + child
  }
}
