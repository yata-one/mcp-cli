///|
suberror ArgError {
  UnknownOption(String)
  UnknownSubcommand(String)
  AmbiguousCommand(String, String, Bool)
  MissingArgument(String)
  TooManyArguments(String)
}

///|
pub impl Show for ArgError with output(self, logger) {
  match self {
    UnknownOption(opt) => {
      logger.write_string("UnknownOption(\"")
      logger.write_string(opt)
      logger.write_string("\")")
    }
    UnknownSubcommand(cmd) => {
      logger.write_string("UnknownSubcommand(\"")
      logger.write_string(cmd)
      logger.write_string("\")")
    }
    AmbiguousCommand(server, tool, has_args) => {
      logger.write_string("AmbiguousCommand(\"")
      logger.write_string(server)
      logger.write_string("\", \"")
      logger.write_string(tool)
      logger.write_string("\", ")
      has_args.output(logger)
      logger.write_string(")")
    }
    MissingArgument(what) => {
      logger.write_string("MissingArgument(\"")
      logger.write_string(what)
      logger.write_string("\")")
    }
    TooManyArguments(cmd) => {
      logger.write_string("TooManyArguments(\"")
      logger.write_string(cmd)
      logger.write_string("\")")
    }
  }
}

///|
pub enum Command {
  List
  Info(String, String?)
  Grep(String)
  Call(String, String, String?)
  Daemon
  Help
  Version
} derive(Show)

///|
pub struct ParsedArgs {
  command : Command
  config_path : String?
} derive(Show)

///|
pub fn parse_args(argv : Array[String]) -> ParsedArgs raise ArgError {
  let mut config_path : String? = None
  let positional = []
  for i = 0; i < argv.length(); {
    let arg = argv[i]
    match arg {
      "-h" | "--help" => return { command: Command::Help, config_path }
      "-v" | "--version" => return { command: Command::Version, config_path }
      "--daemon" => return { command: Command::Daemon, config_path }
      "-c" | "--config" => {
        let next = argv.get(i + 1)
        match next {
          None => raise ArgError::MissingArgument("-c/--config <path>")
          Some(p) => {
            config_path = Some(p)
            continue i + 2
          }
        }
      }
      _ =>
        if arg.has_prefix("-") && arg != "-" {
          raise ArgError::UnknownOption(arg)
        } else {
          positional.push(arg)
          continue i + 1
        }
    }
  } nobreak {
    if positional.is_empty() {
      { command: Command::List, config_path }
    } else {
      parse_command(positional, config_path~)
    }
  }
}

///|
fn parse_command(
  positional : Array[String],
  config_path~ : String?,
) -> ParsedArgs raise ArgError {
  let first = positional[0]
  match first {
    "info" => parse_info(positional[1:], config_path~)
    "grep" => parse_grep(positional[1:], config_path~)
    "call" => parse_call(positional[1:], config_path~)
    _ => {
      if is_possible_subcommand(first) {
        raise ArgError::UnknownSubcommand(first)
      }
      match first.find("/") {
        Some(idx) => {
          let server = first.view(end_offset=idx).to_string()
          let tool = first.view(start_offset=idx + 1).to_string()
          raise ArgError::AmbiguousCommand(
            server,
            tool,
            positional.length() > 1,
          )
        }
        None =>
          if positional.length() >= 2 && is_ambiguous_space_form(positional[1]) {
            raise ArgError::AmbiguousCommand(
              positional[0],
              positional[1],
              positional.length() > 2,
            )
          } else {
            // Default: single server name → info
            { command: Command::Info(first, None), config_path }
          }
      }
    }
  }
}

///|
fn is_possible_subcommand(arg : String) -> Bool {
  match arg.to_lower() {
    "run"
    | "execute"
    | "exec"
    | "invoke"
    | "list"
    | "ls"
    | "get"
    | "show"
    | "describe"
    | "search"
    | "find"
    | "query" => true
    _ => false
  }
}

///|
fn is_ambiguous_space_form(second : String) -> Bool {
  if second.has_prefix("{") || second.has_prefix("[") {
    return false
  }
  looks_like_tool_name(second)
}

///|
fn looks_like_tool_name(s : String) -> Bool {
  let chars = s.to_array()
  match chars.get(0) {
    None => false
    Some(c0) =>
      if !is_tool_start(c0) {
        false
      } else {
        chars[1:].all(is_tool_rest)
      }
  }
}

///|
fn is_tool_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn is_tool_rest(c : Char) -> Bool {
  is_tool_start(c) || (c >= '0' && c <= '9') || c == '-'
}

///|
fn parse_info(
  args : ArrayView[String],
  config_path~ : String?,
) -> ParsedArgs raise ArgError {
  if args.is_empty() {
    raise ArgError::MissingArgument("info <server> [<tool>|<server>/<tool>]")
  }
  let (server, tool, consumed) = parse_server_tool(args)
  if args.length() > consumed {
    raise ArgError::TooManyArguments("info")
  }
  { command: Command::Info(server, tool), config_path }
}

///|
fn parse_grep(
  args : ArrayView[String],
  config_path~ : String?,
) -> ParsedArgs raise ArgError {
  match args.get(0) {
    None => raise ArgError::MissingArgument("grep <glob>")
    Some(pattern) => {
      if args.length() > 1 {
        raise ArgError::TooManyArguments("grep")
      }
      { command: Command::Grep(pattern), config_path }
    }
  }
}

///|
fn parse_call(
  args : ArrayView[String],
  config_path~ : String?,
) -> ParsedArgs raise ArgError {
  if args.is_empty() {
    raise ArgError::MissingArgument("call <server> <tool> [<json>]")
  }
  let (server, tool, consumed) = parse_server_tool(args)
  match tool {
    None => raise ArgError::MissingArgument("call <server> <tool> [<json>]")
    Some(tool) => {
      let rest = args[consumed:].to_array()
      let json_args = if rest.is_empty() {
        None
      } else {
        let joined = rest.join(" ")
        if joined == "-" {
          None
        } else {
          Some(joined)
        }
      }
      { command: Command::Call(server, tool, json_args), config_path }
    }
  }
}

///|
fn parse_server_tool(args : ArrayView[String]) -> (String, String?, Int) {
  let first = args[0]
  match first.find("/") {
    Some(idx) => {
      let server = first.view(end_offset=idx).to_string()
      let tool_part = first.view(start_offset=idx + 1).to_string()
      let tool = if tool_part.is_empty() { None } else { Some(tool_part) }
      (server, tool, 1)
    }
    None => {
      let server = first
      let tool = args.get(1)
      (server, tool, Int::min(2, args.length()))
    }
  }
}
