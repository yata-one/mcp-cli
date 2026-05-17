///|
async fn run_grep(
  command : GrepCommand,
  home : String,
  config_home : String?,
) -> String {
  let paths = @app_paths.mcpx_app_paths(home, config_home~)
  let config = @storage.load_mcpx_config_or_empty(paths.servers_config)
  let now_ms = current_time_millis()
  let cache = load_tool_cache(paths.cache_file)
  let next_cache = Map([])
  let lines = ["Matches for " + command.pattern.to_json().stringify()]
  let skipped = []
  for server_name, server in config.servers {
    let resolved_server = match resolve_runtime_server(server, paths.env_file) {
      Ok(value) => value
      Err(message) => {
        skipped.push(server_name + ": " + message)
        continue
      }
    }
    let key = tool_cache_key(server_name, resolved_server)
    let tools = match cached_tools(cache, key, now_ms) {
      Some(value) => {
        match cache.get(key) {
          Some(entry) => next_cache[key] = entry
          None => ()
        }
        value
      }
      None => {
        let listed = match
          list_configured_server_tools(
            server_name,
            resolved_server,
            home,
            config_home,
            credentials_path=paths.credentials_file,
          ) {
          Ok(value) => value
          Err(message) => {
            skipped.push(server_name + ": " + message)
            continue
          }
        }
        let filtered = @config.filter_tools(resolved_server, listed, tool => {
          tool.name
        })
        next_cache[key] = cache_entry_json(now_ms, server_name, filtered)
        filtered
      }
    }
    for tool in tools {
      if @search.tool_matches(command.pattern, server_name, tool) {
        append_tool_lines(lines, server_name, tool, include_server=true)
      }
    }
  }
  save_tool_cache(paths.cache_file, next_cache)
  let out = if lines.length() == 1 {
    ["No tools matched " + command.pattern.to_json().stringify()]
  } else {
    lines
  }
  append_skipped_lines(out, skipped)
  out.join("\n")
}

///|
async fn list_configured_server_tools(
  server_name : String,
  server : @config.McpServerConfig,
  home : String,
  config_home : String?,
  credentials_path~ : String,
) -> Result[Array[@mcp_client.McpToolInfo], String] {
  match server.transport {
    @config.ServerTransport::Stdio =>
      if is_keep_alive_server(server) {
        let tools = @mcpx_daemon.daemon_list_tools(
          home~,
          config_home~,
          key=daemon_pool_key(server_name, server),
          server~,
        ) catch {
          _ => return Err("mcp daemon error")
        }
        Ok(tools)
      } else {
        let executable = match server.command {
          Some(value) => value
          None => return Err("server has no command: " + server_name)
        }
        let tools = @mcp_stdio.stdio_mcp_list_tools(
          command=executable,
          args=server.args,
          env=server.env,
          cwd=server.cwd,
        ) catch {
          _ => return Err("mcp stdio error")
        }
        Ok(tools)
      }
    @config.ServerTransport::Http =>
      match server.url {
        None => Err("server has no url: " + server_name)
        Some(url) => {
          let headers = match
            call_headers_with_cached_auth(
              server_name~,
              server_url=url,
              server~,
              credentials_path~,
            ) {
            Ok(value) => value
            Err(message) => return Err(message)
          }
          let tools = @mcp_http.http_mcp_list_tools(url~, headers~) catch {
            error => return Err(mcp_http_skip_message(server_name, error))
          }
          Ok(tools)
        }
      }
  }
}

///|
fn append_skipped_lines(lines : Array[String], skipped : Array[String]) -> Unit {
  if skipped.is_empty() {
    return
  }
  lines.push("")
  lines.push("Skipped:")
  for item in skipped {
    lines.push("  " + item)
  }
}

///|
fn load_tool_cache(path : String) -> Map[String, Json] {
  if !@fs.path_exists(path) {
    return Map([])
  }
  let text = @fs.read_file_to_string(path) catch { _ => return Map([]) }
  let json = @json.parse(text) catch { _ => return Map([]) }
  match json {
    Object(obj) =>
      match obj.get("entries") {
        Some(Object(entries)) => entries
        _ => Map([])
      }
    _ => Map([])
  }
}

///|
fn save_tool_cache(path : String, entries : Map[String, Json]) -> Unit {
  @fs.create_dir(parent_dir(path)) catch {
    _ => ()
  }
  let obj = Map([])
  obj["version"] = Json::number(1.0, repr="1")
  obj["entries"] = Json::object(entries)
  @fs.write_string_to_file(path, Json::object(obj).stringify()) catch {
    _ => ()
  }
}

///|
fn parent_dir(path : String) -> String {
  match path.rev_split_once("/") {
    Some((dir, _)) => dir.to_owned()
    None => "."
  }
}

///|
fn cached_tools(
  cache : Map[String, Json],
  key : String,
  now_ms : UInt64,
) -> Array[@mcp_client.McpToolInfo]? {
  match cache.get(key) {
    Some(Object(entry)) => {
      let updated = match entry.get("updatedAtMs") {
        Some(Number(value, ..)) => value.to_uint64()
        _ => return None
      }
      if now_ms > updated && now_ms - updated > 60000UL {
        return None
      }
      match entry.get("tools") {
        Some(Array(values)) => Some(decode_cached_tools(values))
        _ => None
      }
    }
    _ => None
  }
}

///|
fn decode_cached_tools(values : Array[Json]) -> Array[@mcp_client.McpToolInfo] {
  let tools = []
  for value in values {
    match cached_tool_from_json(value) {
      Some(tool) => tools.push(tool)
      None => ()
    }
  }
  tools
}

///|
fn cached_tool_from_json(json : Json) -> @mcp_client.McpToolInfo? {
  match json {
    Object(obj) => {
      let name = match obj.get("name") {
        Some(String(value)) => value
        _ => return None
      }
      let description = match obj.get("description") {
        Some(String(value)) => Some(value)
        _ => None
      }
      let input_schema = obj.get("inputSchema").unwrap_or(Json::object({}))
      Some(@mcp_client.mcp_tool_info(name~, description~, input_schema~))
    }
    _ => None
  }
}

///|
fn cache_entry_json(
  updated_at_ms : UInt64,
  server_name : String,
  tools : Array[@mcp_client.McpToolInfo],
) -> Json {
  let obj = Map([])
  obj["updatedAtMs"] = Json::number(
    updated_at_ms.to_double(),
    repr=updated_at_ms.to_string(),
  )
  obj["server"] = Json::string(server_name)
  obj["tools"] = Json::array(tools.map(tool_info_json))
  Json::object(obj)
}
