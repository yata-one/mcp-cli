///|
test "mcp client session: tracks initialization and request ids" {
  let client = mcp_client(client_name="mcpx", client_version="0.1.0")
  inspect(client.is_initialized(), content="false")
  let init = client.initialize_request()
  @debug.debug_inspect(init.id, content="Some(1)")
  let response = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "result": Json::object({
      "protocolVersion": Json::string("2025-03-26"),
      "capabilities": Json::object({}),
      "serverInfo": Json::object({ "name": Json::string("srv") }),
    }),
  })
  let info = client.accept_initialize_response(init, response) catch {
    _ => abort("unexpected mcp protocol error")
  }
  @debug.debug_inspect(
    info.server_name,
    content=(
      #|Some("srv")
    ),
  )
  inspect(client.is_initialized(), content="true")
  let list = client.tools_list_request()
  @debug.debug_inspect(list.id, content="Some(2)")
}
