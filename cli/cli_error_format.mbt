///|
/// CLI error formatting (user-facing).

///|
pub fn describe_transport(transport : Transport) -> String {
  match transport {
    Transport::Http(url, _) => "http " + url
    Transport::Stdio(command, args, _, cwd) => {
      let cmdline = if args.is_empty() {
        command
      } else {
        command + " " + args.join(" ")
      }
      match cwd {
        None => "stdio " + cmdline
        Some(dir) => "stdio " + cmdline + " (cwd: " + dir + ")"
      }
    }
  }
}

///|
pub fn format_cli_error(
  err : Error,
  debug? : Bool = false,
  config_path? : String? = None,
  server? : String? = None,
  tool? : String? = None,
  transport? : Transport? = None,
) -> String {
  let target = format_target(server, tool)
  let transport_desc = match transport {
    None => None
    Some(t) => Some(describe_transport(t))
  }
  let base = match err {
    ArgError::UnknownOption(opt) =>
      "Error: unknown option: " + opt + "\n  Tip: run 'mcp-cli --help'"
    ArgError::UnknownSubcommand(cmd) =>
      "Error: unknown subcommand: " +
      cmd +
      "\n  Tip: available subcommands: info, grep, call" +
      "\n  Tip: run 'mcp-cli --help'"
    ArgError::AmbiguousCommand(s, t, has_args) =>
      format_ambiguous_command(s, t, has_args)
    ArgError::MissingArgument(what) =>
      "Error: missing argument\n  Expected: " +
      what +
      "\n  Tip: run 'mcp-cli --help'"
    ArgError::TooManyArguments(cmd) =>
      "Error: too many arguments for '" + cmd + "'\n  Tip: run 'mcp-cli --help'"
    ConfigError::ConfigNotFound => format_config_not_found(config_path)
    ConfigError::ReadFailed(path, msg) =>
      "Error: failed to read config file: " + path + "\n  " + msg
    ConfigError::InvalidJsonc =>
      "Error: config file is not valid JSONC" +
      format_optional_path(config_path) +
      "\n  Tip: check for unterminated strings/comments"
    ConfigError::InvalidJson(msg) =>
      "Error: config file contains invalid JSON" +
      format_optional_path(config_path) +
      "\n  " +
      msg
    ConfigError::InvalidRoot =>
      "Error: config root must be a JSON object (with \"mcpServers\")"
    ConfigError::MissingField(key) =>
      "Error: config is missing required field: " + key
    ConfigError::InvalidField(key) =>
      "Error: config field has invalid type: " + key
    ConfigError::InvalidServer(name, msg) =>
      "Error: invalid server \"" + name + "\": " + msg
    ConfigError::MissingEnvVar(name) =>
      "Error: missing environment variable: " +
      name +
      "\n  Tip: set MCP_STRICT_ENV=false to ignore missing vars"
    ConfigError::InvalidEnvVarSyntax(raw) =>
      "Error: invalid env var placeholder: " +
      raw +
      "\n  Tip: use ${NAME} (e.g. ${API_KEY})"
    SettingsError::InvalidEnvVar(name, value) =>
      format_settings_env_error(name, value)
    JsonArgsError::InvalidJson(msg) =>
      "Error: invalid JSON arguments\n  " +
      msg +
      "\n  Tip: arguments must be a JSON object, e.g. '{}' or '{\"text\":\"hi\"}'"
    JsonArgsError::ArgsMustBeObject =>
      "Error: tool arguments must be a JSON object\n  Tip: pass '{}' or '{\"key\":\"value\"}'"
    McpError::RemoteError(code, msg) => format_remote_error(target, code, msg)
    McpError::Protocol(msg) =>
      "Error: protocol error" + format_optional_target(target) + "\n  " + msg
    McpError::UnexpectedEof =>
      "Error: connection closed unexpectedly" + format_optional_target(target)
    McpError::Transport(te) =>
      format_transport_error(target, transport_desc, te)
    DaemonError::Unavailable =>
      "Error: daemon unavailable\n  Tip: set MCP_NO_DAEMON=1 to disable daemon usage"
    DaemonError::ConnectFailed(msg) =>
      "Error: failed to connect to daemon\n  " +
      msg +
      "\n  Tip: set MCP_NO_DAEMON=1 to disable daemon usage"
    DaemonError::SpawnFailed(msg) => "Error: failed to start daemon\n  " + msg
    DaemonError::StartTimeout =>
      "Error: daemon did not start in time\n  Tip: set MCP_NO_DAEMON=1 to disable daemon usage"
    DaemonError::InvalidResponse(msg) =>
      "Error: daemon returned invalid response\n  " + msg
    DaemonError::RemoteError(msg) => "Error: daemon error\n  " + msg
    TransportError::Closed =>
      format_transport_error(target, transport_desc, TransportError::Closed)
    TransportError::SpawnFailed(msg) =>
      format_transport_error(
        target,
        transport_desc,
        TransportError::SpawnFailed(msg),
      )
    TransportError::ReadFailed(msg) =>
      format_transport_error(
        target,
        transport_desc,
        TransportError::ReadFailed(msg),
      )
    TransportError::WriteFailed(msg) =>
      format_transport_error(
        target,
        transport_desc,
        TransportError::WriteFailed(msg),
      )
    TransportError::InvalidJson(msg) =>
      format_transport_error(
        target,
        transport_desc,
        TransportError::InvalidJson(msg),
      )
    StateError::WriteFailed(msg) =>
      "Error: failed to write daemon state file\n  " + msg
    _ => "Error: " + err.to_string()
  }
  if debug {
    base + "\n\nDebug:\n  " + err.to_string()
  } else {
    base
  }
}

///|
fn format_target(server : String?, tool : String?) -> String? {
  match (server, tool) {
    (Some(s), Some(t)) => Some(s + "/" + t)
    (Some(s), None) => Some(s)
    _ => None
  }
}

///|
fn format_optional_target(target : String?) -> String {
  match target {
    None => ""
    Some(t) => " (" + t + ")"
  }
}

///|
fn format_optional_path(path : String?) -> String {
  match path {
    None => ""
    Some(p) => " (" + p + ")"
  }
}

///|
fn format_config_not_found(config_path : String?) -> String {
  match config_path {
    Some(p) =>
      "Error: config file not found: " +
      p +
      "\n  Tip: config supports JSONC (comments + trailing commas)"
    None => {
      let searched = default_config_paths().map(p => "    - " + p).join("\n")
      "Error: config file not found\n  Searched:\n" +
      searched +
      "\n  Tip: use -c/--config to specify a file path" +
      "\n  Tip: config supports JSONC (comments + trailing commas)"
    }
  }
}

///|
fn format_ambiguous_command(
  server : String,
  tool : String,
  has_args : Bool,
) -> String {
  let target = server + "/" + tool
  if has_args {
    "Error: ambiguous command: " +
    target +
    "\n  Tip: use 'mcp-cli call " +
    server +
    " " +
    tool +
    " <json>' to run the tool" +
    "\n  Tip: use 'mcp-cli info " +
    server +
    " " +
    tool +
    "' to show schema"
  } else {
    "Error: ambiguous command: " +
    target +
    "\n  Tip: use 'mcp-cli info " +
    server +
    " " +
    tool +
    "' to show schema" +
    "\n  Tip: use 'mcp-cli call " +
    server +
    " " +
    tool +
    " <json>' to run the tool"
  }
}

///|
fn format_settings_env_error(name : String, value : String) -> String {
  let hint = match name {
    "MCP_DEBUG" | "MCP_NO_DAEMON" => "expected 1/0/true/false"
    "MCP_MAX_RETRIES" | "MCP_RETRY_DELAY" => "expected a non-negative integer"
    _ => "expected a positive integer"
  }
  "Error: invalid environment variable: " +
  name +
  "=" +
  value +
  "\n  Tip: " +
  hint
}

///|
fn format_remote_error(target : String?, code : Int, msg : String) -> String {
  let scope = match target {
    None => ""
    Some(t) => " from " + t
  }
  "Error: remote error" + scope + " (code " + code.to_string() + ")\n  " + msg
}

///|
fn format_transport_error(
  target : String?,
  transport_desc : String?,
  err : TransportError,
) -> String {
  let scope = match target {
    None => ""
    Some(t) => " (" + t + ")"
  }
  let transport_line = match transport_desc {
    None => ""
    Some(desc) => "\n  Transport: " + desc
  }
  match err {
    TransportError::Closed =>
      "Error: connection is closed" + scope + transport_line
    TransportError::SpawnFailed(msg) =>
      "Error: failed to start server process" +
      scope +
      transport_line +
      "\n  " +
      msg
    TransportError::ReadFailed(msg) =>
      "Error: transport read failed" + scope + transport_line + "\n  " + msg
    TransportError::WriteFailed(msg) =>
      "Error: transport write failed" + scope + transport_line + "\n  " + msg
    TransportError::InvalidJson(msg) =>
      "Error: server returned invalid JSON" +
      scope +
      transport_line +
      "\n  " +
      msg
  }
}
