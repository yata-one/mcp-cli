///|
pub fn render_mcpx_command(command : McpxCommand) -> String {
  match command {
    Help => mcpx_help_text()
    Version => "mcpx 0.1.0"
    CallHelp => call_help_text()
    Call(command) => render_call_command(command)
    Info(command) => render_info_command(command)
    GrepHelp => grep_help_text()
    Grep(command) => render_grep_command(command)
    AuthHelp => auth_help_text()
    Auth(command) => render_auth_command(command)
    Daemon(command) => render_daemon_command(command)
  }
}

///|
pub fn mcpx_help_text() -> String {
  (
    #|mcpx - Native MCP CLI
    #|
    #|Usage:
    #|  mcpx
    #|  mcpx --help
    #|  mcpx --version
    #|
    #|  mcpx info
    #|  mcpx info <server|mcp-url>
    #|  mcpx info <server|mcp-url> <tool>
    #|  mcpx grep <pattern>
    #|  mcpx call <server|mcp-url> <tool> [arguments-json]
    #|
    #|  mcpx auth <server>
    #|  mcpx auth <server> --no-browser --json
    #|  mcpx auth <server> --code <code> --state <state>
    #|
    #|  mcpx daemon status
    #|  mcpx daemon stop
  )
}

///|
pub fn call_help_text() -> String {
  (
    #|mcpx call
    #|
    #|Usage:
    #|  mcpx call <server|mcp-url> <tool>
    #|  mcpx call <server|mcp-url> <tool> <arguments-json>
    #|
    #|Examples:
    #|  mcpx call github search '{"q":"moonbit"}'
    #|  echo '{"q":"moonbit"}' | mcpx call github search
  )
}

///|
pub fn grep_help_text() -> String {
  (
    #|mcpx grep
    #|
    #|Usage:
    #|  mcpx grep <pattern>
  )
}

///|
pub fn auth_help_text() -> String {
  (
    #|mcpx auth
    #|
    #|Usage:
    #|  mcpx auth <server>
    #|  mcpx auth <server> --no-browser --json
    #|  mcpx auth <server> --code <code> --state <state>
  )
}

///|
pub fn daemon_help_text() -> String {
  (
    #|mcpx daemon
    #|
    #|Usage:
    #|  mcpx daemon status
    #|  mcpx daemon stop
  )
}

///|
fn render_call_command(command : CallCommand) -> String {
  let obj = Map([])
  obj["action"] = Json::string("call")
  obj["server"] = Json::string(command.server)
  match command.url {
    Some(value) => obj["url"] = Json::string(value)
    None => ()
  }
  obj["tool"] = Json::string(command.tool)
  match command.arguments_json {
    Some(arguments) => obj["arguments"] = Json::string(arguments)
    None => ()
  }
  Json::object(obj).stringify()
}

///|
fn render_info_command(command : InfoCommand) -> String {
  let obj = Map([])
  obj["action"] = Json::string("info")
  match command.server {
    Some(value) => obj["server"] = Json::string(value)
    None => ()
  }
  match command.url {
    Some(value) => obj["url"] = Json::string(value)
    None => ()
  }
  match command.tool {
    Some(value) => obj["tool"] = Json::string(value)
    None => ()
  }
  Json::object(obj).stringify()
}

///|
fn render_grep_command(command : GrepCommand) -> String {
  let obj = Map([])
  obj["action"] = Json::string("grep")
  obj["pattern"] = Json::string(command.pattern)
  Json::object(obj).stringify()
}

///|
fn render_auth_command(command : AuthCommand) -> String {
  let obj = Map([])
  obj["action"] = Json::string("auth")
  obj["server"] = Json::string(command.server)
  obj["noBrowser"] = Json::boolean(command.no_browser)
  obj["json"] = Json::boolean(command.json_output)
  match command.code {
    Some(_) => obj["codeProvided"] = Json::boolean(true)
    None => ()
  }
  match command.state {
    Some(_) => obj["stateProvided"] = Json::boolean(true)
    None => ()
  }
  Json::object(obj).stringify()
}

///|
fn render_daemon_command(command : DaemonCommand) -> String {
  match command.mode {
    DaemonMode::Help => return daemon_help_text()
    _ => ()
  }
  let obj = Map([])
  obj["action"] = Json::string("daemon")
  obj["mode"] = Json::string(daemon_mode_to_string(command.mode))
  Json::object(obj).stringify()
}

///|
fn daemon_mode_to_string(mode : DaemonMode) -> String {
  match mode {
    Help => "help"
    Status => "status"
    Stop => "stop"
  }
}
