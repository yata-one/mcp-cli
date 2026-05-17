///|
test "config store: missing file loads empty config" {
  let path = "/tmp/mcpx-config-store-test/missing/mcpServers.jsonc"
  @fs.remove_file(path) catch {
    _ => ()
  }
  inspect(
    load_mcpx_config_or_empty(path).to_json().stringify(),
    content="{\"mcpServers\":{}}",
  )
}

///|
test "config store: loader only reads the provided path" {
  let jsonc_path = "/tmp/mcpx-config-store-test/no-derived-path/mcpServers.jsonc"
  let json_path = "/tmp/mcpx-config-store-test/no-derived-path/mcpServers.json"
  @fs.remove_file(jsonc_path) catch {
    _ => ()
  }
  @fs.remove_file(json_path) catch {
    _ => ()
  }
  secure_write_private_atomic(
    json_path,
    (
      #|{
      #|  "mcpServers": {
      #|    "github": {
      #|      "transport": "http",
      #|      "url": "https://mcp.github.com/mcp"
      #|    }
      #|  }
      #|}
    ),
  )
  inspect(
    load_mcpx_config_or_empty(jsonc_path).to_json().stringify(),
    content="{\"mcpServers\":{}}",
  )
  inspect(
    load_mcpx_config_or_empty(json_path).to_json().stringify(),
    content=(
      #|{"mcpServers":{"github":{"transport":"http","url":"https://mcp.github.com/mcp"}}}
    ),
  )
}

///|
test "config store: save writes private config file and loads roundtrip" {
  let path = "/tmp/mcpx-config-store-test/nested/mcpServers.jsonc"
  @fs.remove_file(path) catch {
    _ => ()
  }
  let config = @config.put_remote_mcp_server(
    @config.empty_mcpx_config(),
    name="github",
    url="https://mcp.github.com/mcp",
  )
  save_mcpx_config_file(path, config)
  inspect(mcpx_config_file_mode(path), content="384")
  inspect(
    load_mcpx_config_or_empty(path).to_json().stringify(),
    content=(
      #|{"mcpServers":{"github":{"transport":"http","url":"https://mcp.github.com/mcp"}}}
    ),
  )
}

///|
test "config store: load jsonc and save merged config" {
  let path = "/tmp/mcpx-config-store-test/merge/mcpServers.jsonc"
  let existing =
    #|{
    #|  // existing user config
    #|  "mcpServers": {
    #|    "local": {
    #|      "transport": "stdio",
    #|      "command": "node",
    #|      "args": ["server.js",],
    #|    },
    #|  },
    #|}
  secure_write_private_atomic(path, existing)
  let loaded = load_mcpx_config_or_empty(path)
  save_mcpx_config_file(
    path,
    @config.put_remote_mcp_server(
      loaded,
      name="github",
      url="https://mcp.github.com/mcp",
    ),
  )
  inspect(
    load_mcpx_config_or_empty(path).to_json().stringify(),
    content=(
      #|{"mcpServers":{"local":{"transport":"stdio","command":"node","args":["server.js"]},"github":{"transport":"http","url":"https://mcp.github.com/mcp"}}}
    ),
  )
}
