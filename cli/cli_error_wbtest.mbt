///|
test "cli error: formats unknown command" {
  inspect(
    format_mcpx_parse_error(CliParseError::UnknownCommand("list")),
    content="unknown command: list",
  )
}

///|
test "cli error: formats invalid target" {
  inspect(
    format_mcpx_parse_error(CliParseError::InvalidTarget("github")),
    content="invalid target: github (expected server or mcp-url)",
  )
}
