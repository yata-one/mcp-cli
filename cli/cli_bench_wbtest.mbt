///|
test "bench cli parse/render configured call" (it : @bench.T) {
  let args = ["call", "github", "search", "{\"q\":\"moonbit\"}"]
  it.bench(() => {
    match parse_mcpx_args(args) {
      Ok(command) => it.keep(render_mcpx_command(command).length())
      Err(_) => abort("unexpected parse error")
    }
  })
}

///|
test "bench cli parse/render direct URL call" (it : @bench.T) {
  let args = [
    "call", "https://mcp.example.test/mcp", "search", "{\"q\":\"moonbit\"}",
  ]
  it.bench(() => {
    match parse_mcpx_args(args) {
      Ok(command) => it.keep(render_mcpx_command(command).length())
      Err(_) => abort("unexpected parse error")
    }
  })
}
