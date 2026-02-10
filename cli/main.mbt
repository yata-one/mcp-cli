///|
fn main {
  @async.run_async_main(() => run())
}

///|
async fn eprintln(msg : String) -> Unit {
  @stdio.stderr.write(msg + "\n") catch {
    _ => ()
  }
}

///|
async fn[T] die(code : Int, msg : String) -> T {
  eprintln(msg)
  @sys.exit(code)
  panic()
}

///|
async fn load_config_or_die(debug : Bool, config_path : String?) -> Config {
  try {
    match config_path {
      None => load()
      Some(p) => load(config_path=p)
    }
  } catch {
    err => die(1, format_cli_error(err, debug~, config_path~))
  }
}

///|
async fn require_server_or_die(
  cfg : Config,
  server_name : String,
) -> ServerConfig {
  match cfg.servers.get(server_name) {
    Some(s) => s
    None => {
      let names = cfg.servers.keys().to_array()
      names.sort()
      let available = if names.is_empty() {
        ""
      } else {
        "\n  Available: " + names.join(", ")
      }
      die(
        1,
        "Error: unknown server: " +
        server_name +
        available +
        "\n  Tip: run 'mcp-cli' to list servers",
      )
    }
  }
}

///|
async fn run() -> Unit {
  let argv = @sys.get_cli_args()
  let args = if argv.is_empty() { [] } else { argv[1:].to_array() }
  let parsed = parse_args(args) catch { err => die(1, format_cli_error(err)) }
  let settings = settings_from_env(@sys.get_env_vars()) catch {
    err => die(1, format_cli_error(err))
  }
  match parsed.command {
    Help => print_help()
    Version => println("mcp-cli v0.1.0")
    List => cmd_list(settings, parsed.config_path)
    Info(server, tool) => cmd_info(settings, parsed.config_path, server, tool)
    Grep(pattern) => cmd_grep(settings, parsed.config_path, pattern)
    Call(server, tool, args) =>
      cmd_call(settings, parsed.config_path, server, tool, args)
    Daemon => cmd_daemon(settings)
  }
}

///|
fn print_help() -> Unit {
  println(
    (
      #|mcp-cli (MoonBit port) - tools-only
      #|
      #|Usage:
      #|  mcp-cli [options]                              List all servers and tools
      #|  mcp-cli [options] info <server>                Show server details
      #|  mcp-cli [options] info <server> <tool>         Show tool schema
      #|  mcp-cli [options] grep <glob>                  Search tools (glob)
      #|  mcp-cli [options] call <server> <tool> [<json>] Call tool (stdin if no args)
      #|
      #|Formats:
      #|  mcp-cli info server tool
      #|  mcp-cli info server/tool
      #|  mcp-cli call server tool '{}'
      #|  mcp-cli call server/tool '{}'
      #|
      #|Output:
      #|  mcp-cli/info/grep  Human-readable text to stdout
      #|  call               Raw text (fallback JSON) to stdout
      #|  Errors/warnings    Always to stderr
      #|
      #|Options:
      #|  -h, --help               Show help
      #|  -v, --version            Show version
      #|  -c, --config <path>      Path to config file
      #|
      #|Config discovery (when -c/--config is not set):
      #|  $HOME/.agents/mcp-cli.json
      #|  $HOME/.agents/mcp-cli.jsonc
      #|  {project-root}/.agents/mcp-cli.json
      #|  {project-root}/.agents/mcp-cli.jsonc
      #|
      #|Environment variables:
      #|  MCP_NO_DAEMON=1        Disable connection caching
      #|  MCP_DAEMON_TIMEOUT=N   Daemon idle timeout seconds (default: 60)
      #|  MCP_TIMEOUT=N          Timeout seconds (default: 1800)
      #|  MCP_CONCURRENCY=N      Max parallel servers (default: 5)
      #|  MCP_MAX_RETRIES=N      Retry attempts (default: 3)
      #|  MCP_RETRY_DELAY=N      Retry delay ms (default: 1000)
      #|  MCP_DEBUG=1            Debug logs to stderr
    ),
  )
}

///|
async fn cmd_daemon(settings : Settings) -> Unit {
  run_daemon(settings)
}

///|
async fn cmd_list(settings : Settings, config_path : String?) -> Unit {
  let cfg = load_config_or_die(settings.debug, config_path)
  let names = cfg.servers.keys().to_array()
  names.sort()
  if names.is_empty() {
    eprintln("Warning: no servers configured")
    return ()
  }
  let servers = map_limit(names, settings.concurrency, name => {
    let server = cfg.servers.get(name).unwrap()
    let result : Result[ServerView, _] = try? ({
      let (tools, instructions) = list_tools_with_meta(settings, server)
      let views = tools
        .filter(t => is_tool_allowed(t.name, server))
        .map(to_tool_view)
      match instructions {
        None => server_view(name, views)
        Some(text) => server_view(name, views, instructions=text)
      }
    })
    match result {
      Ok(view) => view
      Err(err) =>
        server_view(name, [
          tool_view(
            "<error: " + err.to_string() + ">",
            input_schema=Json::object({}),
          ),
        ])
    }
  })
  println(format_server_list(servers))
}

///|
fn to_tool_view(tool : ToolInfo) -> ToolView {
  match tool.description {
    None => tool_view(tool.name, input_schema=tool.input_schema)
    Some(desc) =>
      tool_view(tool.name, description=desc, input_schema=tool.input_schema)
  }
}

///|
async fn cmd_info(
  settings : Settings,
  config_path : String?,
  server_name : String,
  tool_name : String?,
) -> Unit {
  let cfg = load_config_or_die(settings.debug, config_path)
  let server = require_server_or_die(cfg, server_name)
  let result : Result[Unit, _] = try? ({
    let (tools, instructions) = list_tools_with_meta(settings, server)
    let views = tools
      .filter(t => is_tool_allowed(t.name, server))
      .map(to_tool_view)
    match tool_name {
      None =>
        println(format_server_details(server_name, server, views, instructions))
      Some(name) =>
        match views.iter().find_first(v => v.name == name) {
          None => {
            eprintln(
              "Error: tool not found: " +
              name +
              "\n  Tip: run 'mcp-cli info " +
              server_name +
              "' to list available tools",
            )
            @sys.exit(1)
          }
          Some(tool) => println(format_tool_schema(server_name, tool))
        }
    }
  })
  match result {
    Ok(_) => ()
    Err(err) => {
      eprintln(
        format_cli_error(
          err,
          debug=settings.debug,
          server=Some(server_name),
          tool=tool_name,
          transport=Some(server.transport),
        ),
      )
      @sys.exit(exit_code_of_error(err))
    }
  }
}

///|
async fn cmd_grep(
  settings : Settings,
  config_path : String?,
  pattern : String,
) -> Unit {
  let cfg = load_config_or_die(settings.debug, config_path)
  let names = cfg.servers.keys().to_array()
  names.sort()
  if names.is_empty() {
    eprintln("Warning: no servers configured")
    return ()
  }
  let outcomes = map_limit(names, settings.concurrency, name => {
    let server = cfg.servers.get(name).unwrap()
    let r : Result[Array[ToolView], _] = try? ({
      let (tools, _) = list_tools_with_meta(settings, server)
      tools
      .filter(t => is_tool_allowed(t.name, server))
      .filter(t => matches_pattern(t.name, pattern))
      .map(to_tool_view)
    })
    match r {
      Ok(views) => (name, views, false)
      Err(_) => (name, [], true)
    }
  })
  let results : Array[(String, ToolView)] = []
  let failed : Array[String] = []
  for outcome in outcomes {
    let (name, views, is_failed) = outcome
    if is_failed {
      failed.push(name)
    } else {
      for v in views {
        results.push((name, v))
      }
    }
  }
  if !failed.is_empty() {
    eprintln(
      "Warning: " +
      failed.length().to_string() +
      " server(s) failed: " +
      failed.join(", "),
    )
  }
  if results.is_empty() {
    println("No tools found matching \"" + pattern + "\"")
    println("  Tip: Pattern matches tool names only (not server names)")
    println("  Tip: Use '*' for wildcards, e.g. '*file*' or 'read_*'")
    println("  Tip: Run 'mcp-cli' to list all available tools")
  } else {
    println(format_search_results(results))
  }
}

///|
async fn cmd_call(
  settings : Settings,
  config_path : String?,
  server_name : String,
  tool_name : String,
  args : String?,
) -> Unit {
  let cfg = load_config_or_die(settings.debug, config_path)
  let server = require_server_or_die(cfg, server_name)
  if !is_tool_allowed(tool_name, server) {
    eprintln(
      "Error: tool \"" +
      tool_name +
      "\" is disabled by configuration\n  Tip: check allowedTools/disabledTools",
    )
    @sys.exit(1)
    return ()
  }
  let args_json = match args {
    Some(s) =>
      parse_json_args(s) catch {
        err => die(1, format_cli_error(err, debug=settings.debug))
      }
    None =>
      if stdin_is_tty() {
        Json::object({})
      } else {
        let text = @stdio.stdin.read_all().text() catch {
            err => die(1, format_cli_error(err, debug=settings.debug))
          }
        parse_json_args(text) catch {
          err => die(1, format_cli_error(err, debug=settings.debug))
        }
      }
  }
  let r : Result[Json, _] = try? call_tool(
    settings, server, tool_name, args_json,
  )
  match r {
    Ok(result) => println(format_tool_result(result))
    Err(err) => {
      eprintln(
        format_cli_error(
          err,
          debug=settings.debug,
          server=Some(server_name),
          tool=Some(tool_name),
          transport=Some(server.transport),
        ),
      )
      @sys.exit(exit_code_of_error(err))
    }
  }
}

///|
async fn list_tools_with_meta(
  settings : Settings,
  server : ServerConfig,
) -> (Array[ToolInfo], String?) {
  if settings.no_daemon {
    direct_list_tools_with_meta(settings, server)
  } else {
    let result : Result[(Array[ToolInfo], String?), Error] = try? daemon_list_tools(
      settings, server,
    )
    match result {
      Ok(v) => v
      Err(_) => direct_list_tools_with_meta(settings, server)
    }
  }
}

///|
async fn direct_list_tools_with_meta(
  settings : Settings,
  server : ServerConfig,
) -> (Array[ToolInfo], String?) {
  @async.retry(
    @async.RetryMethod::FixedDelay(settings.retry_delay_ms),
    () => {
      @async.with_timeout(settings.timeout_ms, () => {
        match server.transport {
          Transport::Http(url, headers) => list_tools_http(url, headers)
          Transport::Stdio(command, args, env, cwd) =>
            @async.with_task_group(group => {
              list_tools_stdio(group, command, args, env, cwd)
            })
        }
      })
    },
    max_retry=settings.max_retries,
    fatal_error=is_fatal_retry_error,
  )
}

///|
async fn[T : McpTransport, U] with_initialized_client(
  client : Client[T],
  op : async (Client[T]) -> U,
) -> U {
  let result : Result[U, _] = try? ({
    client.initialize(client_version="0.1.0")
    op(client)
  })
  client.close() catch {
    _ => ()
  }
  match result {
    Ok(v) => v
    Err(err) => raise err
  }
}

///|
async fn list_tools_http(
  url : String,
  headers : Map[String, String],
) -> (Array[ToolInfo], String?) {
  let transport = http_transport(url, headers)
  let client = client(transport)
  with_initialized_client(client, client => {
    let tools = client.list_tools()
    (tools, client.get_instructions())
  })
}

///|
async fn[X] list_tools_stdio(
  group : @async.TaskGroup[X],
  command : String,
  args : Array[String],
  env : Map[String, String],
  cwd : String?,
) -> (Array[ToolInfo], String?) {
  let transport = connect_stdio(group, command, args, env, cwd)
  let client = client(transport)
  with_initialized_client(client, client => {
    let tools = client.list_tools()
    (tools, client.get_instructions())
  })
}

///|
async fn call_tool(
  settings : Settings,
  server : ServerConfig,
  tool_name : String,
  args_json : Json,
) -> Json {
  if settings.no_daemon {
    direct_call_tool(settings, server, tool_name, args_json)
  } else {
    let result : Result[Json, Error] = try? daemon_call_tool(
      settings, server, tool_name, args_json,
    )
    match result {
      Ok(v) => v
      Err(DaemonError::Unavailable) =>
        direct_call_tool(settings, server, tool_name, args_json)
      Err(DaemonError::ConnectFailed(_)) =>
        direct_call_tool(settings, server, tool_name, args_json)
      Err(DaemonError::SpawnFailed(_)) =>
        direct_call_tool(settings, server, tool_name, args_json)
      Err(DaemonError::StartTimeout) =>
        direct_call_tool(settings, server, tool_name, args_json)
      Err(err) => raise err
    }
  }
}

///|
async fn direct_call_tool(
  settings : Settings,
  server : ServerConfig,
  tool_name : String,
  args_json : Json,
) -> Json {
  @async.retry(
    @async.RetryMethod::FixedDelay(settings.retry_delay_ms),
    () => {
      @async.with_timeout(settings.timeout_ms, () => {
        match server.transport {
          Transport::Http(url, headers) =>
            call_tool_http(url, headers, tool_name, args_json)
          Transport::Stdio(command, args, env, cwd) =>
            @async.with_task_group(group => {
              call_tool_stdio(
                group, command, args, env, cwd, tool_name, args_json,
              )
            })
        }
      })
    },
    max_retry=settings.max_retries,
    fatal_error=is_fatal_retry_error,
  )
}

///|
async fn call_tool_http(
  url : String,
  headers : Map[String, String],
  tool_name : String,
  args_json : Json,
) -> Json {
  let transport = http_transport(url, headers)
  let client = client(transport)
  with_initialized_client(client, client => {
    client.call_tool(tool_name, args_json)
  })
}

///|
async fn[X] call_tool_stdio(
  group : @async.TaskGroup[X],
  command : String,
  args : Array[String],
  env : Map[String, String],
  cwd : String?,
  tool_name : String,
  args_json : Json,
) -> Json {
  let transport = connect_stdio(group, command, args, env, cwd)
  let client = client(transport)
  with_initialized_client(client, client => {
    client.call_tool(tool_name, args_json)
  })
}

///|
fn is_fatal_retry_error(err : Error) -> Bool {
  match err {
    McpError::RemoteError(_, _) => true
    McpError::Protocol(_) => true
    _ => false
  }
}

///|
fn exit_code_of_error(err : Error) -> Int {
  match err {
    McpError::RemoteError(_, _) => 2
    DaemonError::RemoteError(_) => 2
    McpError::Transport(_) => 3
    McpError::Protocol(_) => 3
    McpError::UnexpectedEof => 3
    DaemonError::Unavailable => 3
    DaemonError::ConnectFailed(_) => 3
    DaemonError::SpawnFailed(_) => 3
    DaemonError::StartTimeout => 3
    DaemonError::InvalidResponse(_) => 3
    _ => 1
  }
}
