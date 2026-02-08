///|
test "settings_from_env: defaults" {
  let s = settings_from_env({})
  inspect(s.debug, content="false")
  inspect(s.timeout_ms, content="1800000")
  inspect(s.concurrency, content="5")
  inspect(s.max_retries, content="3")
  inspect(s.retry_delay_ms, content="1000")
  inspect(s.no_daemon, content="false")
  inspect(s.daemon_timeout_ms, content="60000")
}

///|
test "settings_from_env: parses MCP_* overrides" {
  let env = {
    "MCP_DEBUG": "1",
    "MCP_TIMEOUT": "10",
    "MCP_CONCURRENCY": "2",
    "MCP_MAX_RETRIES": "0",
    "MCP_RETRY_DELAY": "250",
    "MCP_NO_DAEMON": "true",
    "MCP_DAEMON_TIMEOUT": "5",
  }
  let s = settings_from_env(env)
  inspect(s.debug, content="true")
  inspect(s.timeout_ms, content="10000")
  inspect(s.concurrency, content="2")
  inspect(s.max_retries, content="0")
  inspect(s.retry_delay_ms, content="250")
  inspect(s.no_daemon, content="true")
  inspect(s.daemon_timeout_ms, content="5000")
}

///|
test "settings_from_env: invalid int raises" {
  let r : Result[Settings, SettingsError] = try? settings_from_env({
    "MCP_TIMEOUT": "abc",
  })
  inspect(r, content="Err(InvalidEnvVar(\"MCP_TIMEOUT\", \"abc\"))")
}
