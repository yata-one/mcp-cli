///|
test "mcp client request: builds initialize notification list and call" {
  inspect(
    mcp_initialize_request(id=1, client_name="mcpx", client_version="0.1.0").stringify(),
    content=(
      #|{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"mcpx","version":"0.1.0"}}}
    ),
  )
  inspect(
    mcp_initialized_notification().stringify(),
    content="{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
  )
  inspect(
    mcp_tools_list_request(id=2).stringify(),
    content="{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}",
  )
  inspect(
    mcp_tool_call_request(
      id=3,
      name="search",
      arguments=Json::object({ "q": Json::string("moonbit") }),
    ).stringify(),
    content=(
      #|{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search","arguments":{"q":"moonbit"}}}
    ),
  )
}
