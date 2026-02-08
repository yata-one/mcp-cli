///|
test "format_cli_error: ambiguous command" {
  let r : Result[ParsedArgs, _] = try? parse_args(["srv/echo"])
  let msg = match r {
    Ok(_) => fail("expected error")
    Err(err) => format_cli_error(err)
  }
  inspect(
    msg,
    content="Error: ambiguous command: srv/echo\n  Tip: use 'mcp-cli info srv echo' to show schema\n  Tip: use 'mcp-cli call srv echo <json>' to run the tool",
  )
}

///|
test "format_cli_error: config not found (-c)" {
  let path = "/tmp/mcp-cli-cli_error_format_test-does-not-exist.jsonc"
  let r : Result[Config, _] = try? load(config_path=path)
  let msg = match r {
    Ok(_) => fail("expected error")
    Err(err) => format_cli_error(err, config_path=Some(path))
  }
  inspect(
    msg,
    content="Error: config file not found: /tmp/mcp-cli-cli_error_format_test-does-not-exist.jsonc\n  Tip: config supports JSONC (comments + trailing commas)",
  )
}

///|
test "format_cli_error: invalid settings env var" {
  let r : Result[Settings, _] = try? settings_from_env({ "MCP_DEBUG": "lol" })
  let msg = match r {
    Ok(_) => fail("expected error")
    Err(err) => format_cli_error(err)
  }
  inspect(
    msg,
    content="Error: invalid environment variable: MCP_DEBUG=lol\n  Tip: expected 1/0/true/false",
  )
}

///|
test "format_cli_error: json args must be object" {
  let r : Result[Json, _] = try? parse_json_args("[1]")
  let msg = match r {
    Ok(_) => fail("expected error")
    Err(err) => format_cli_error(err)
  }
  inspect(
    msg,
    content="Error: tool arguments must be a JSON object\n  Tip: pass '{}' or '{\"key\":\"value\"}'",
  )
}

///|
async test "format_cli_error: transport error with context" {
  let cfg = parse_jsonc(
    (
      #|{
      #|  "mcpServers": {
      #|    "s": { "url": "http://example.com/mcp" }
      #|  }
      #|}
    ),
  )
  let server = cfg.servers.get("s").unwrap()
  let transport = mock_transport([])
  transport.close()
  let c = client(transport)
  let r : Result[Json, _] = try? c.call_tool("echo", Json::object({}))
  let msg = match r {
    Ok(_) => fail("expected error")
    Err(err) =>
      format_cli_error(
        err,
        server=Some("s"),
        tool=Some("echo"),
        transport=Some(server.transport),
      )
  }
  inspect(
    msg,
    content="Error: connection is closed (s/echo)\n  Transport: http http://example.com/mcp",
  )
}
