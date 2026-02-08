///|
suberror SettingsError {
  InvalidEnvVar(String, String)
}

///|
pub impl Show for SettingsError with output(self, logger) {
  match self {
    InvalidEnvVar(name, value) => {
      logger.write_string("InvalidEnvVar(\"")
      logger.write_string(name)
      logger.write_string("\", \"")
      logger.write_string(value)
      logger.write_string("\")")
    }
  }
}

///|
pub struct Settings {
  debug : Bool
  timeout_ms : Int
  concurrency : Int
  max_retries : Int
  retry_delay_ms : Int
  no_daemon : Bool
  daemon_timeout_ms : Int
} derive(Show)

///|
pub fn settings_from_env(
  env : Map[String, String],
) -> Settings raise SettingsError {
  let debug = parse_bool_env(env, "MCP_DEBUG", false)
  let timeout_s = parse_int_env(env, "MCP_TIMEOUT", 1800)
  if timeout_s <= 0 {
    raise SettingsError::InvalidEnvVar(
      "MCP_TIMEOUT",
      env.get("MCP_TIMEOUT").unwrap(),
    )
  }
  let concurrency = parse_int_env(env, "MCP_CONCURRENCY", 5)
  if concurrency <= 0 {
    raise SettingsError::InvalidEnvVar(
      "MCP_CONCURRENCY",
      env.get("MCP_CONCURRENCY").unwrap(),
    )
  }
  let max_retries = parse_int_env(env, "MCP_MAX_RETRIES", 3)
  if max_retries < 0 {
    raise SettingsError::InvalidEnvVar(
      "MCP_MAX_RETRIES",
      env.get("MCP_MAX_RETRIES").unwrap(),
    )
  }
  let retry_delay_ms = parse_int_env(env, "MCP_RETRY_DELAY", 1000)
  if retry_delay_ms < 0 {
    raise SettingsError::InvalidEnvVar(
      "MCP_RETRY_DELAY",
      env.get("MCP_RETRY_DELAY").unwrap(),
    )
  }
  let no_daemon = parse_bool_env(env, "MCP_NO_DAEMON", false)
  let daemon_timeout_s = parse_int_env(env, "MCP_DAEMON_TIMEOUT", 60)
  if daemon_timeout_s <= 0 {
    raise SettingsError::InvalidEnvVar(
      "MCP_DAEMON_TIMEOUT",
      env.get("MCP_DAEMON_TIMEOUT").unwrap(),
    )
  }
  {
    debug,
    timeout_ms: timeout_s * 1000,
    concurrency,
    max_retries,
    retry_delay_ms,
    no_daemon,
    daemon_timeout_ms: daemon_timeout_s * 1000,
  }
}

///|
fn parse_bool_env(
  env : Map[String, String],
  name : String,
  default : Bool,
) -> Bool raise SettingsError {
  match env.get(name) {
    None => default
    Some("1") | Some("true") => true
    Some("0") | Some("false") => false
    Some(value) => raise SettingsError::InvalidEnvVar(name, value)
  }
}

///|
fn parse_int_env(
  env : Map[String, String],
  name : String,
  default : Int,
) -> Int raise SettingsError {
  match env.get(name) {
    None => default
    Some(value) =>
      @strconv.parse_int(value.to_string_view(), base=10) catch {
        _ => raise SettingsError::InvalidEnvVar(name, value)
      }
  }
}
