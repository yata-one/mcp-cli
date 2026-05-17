///|
test "mcp client response: decodes initialize tool list and call result" {
  let init = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "result": Json::object({
      "protocolVersion": Json::string("2025-03-26"),
      "capabilities": Json::object({}),
      "serverInfo": Json::object({ "name": Json::string("srv") }),
    }),
  })
  @debug.debug_inspect(
    decode_mcp_initialize_response(init, expected_id=1),
    content=(
      #|Ok(
      #|  {
      #|    protocol_version: "2025-03-26",
      #|    server_name: Some("srv"),
      #|    server_version: None,
      #|    capabilities: Object({}),
      #|  },
      #|)
    ),
  )
  let list = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(2.0, repr="2"),
    "result": Json::object({
      "tools": Json::array([
        Json::object({
          "name": Json::string("search"),
          "description": Json::string("Search things"),
          "inputSchema": Json::object({ "type": Json::string("object") }),
        }),
      ]),
    }),
  })
  @debug.debug_inspect(
    decode_mcp_tool_list_response(list, expected_id=2),
    content=(
      #|Ok(
      #|  [
      #|    {
      #|      name: "search",
      #|      description: Some("Search things"),
      #|      input_schema: Object({ "type": String("object") }),
      #|    },
      #|  ],
      #|)
    ),
  )
  let call = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(3.0, repr="3"),
    "result": Json::object({ "ok": Json::boolean(true) }),
  })
  inspect(
    (decode_mcp_result(call, expected_id=3) catch { _ => Json::object({}) }).stringify(),
    content="{\"ok\":true}",
  )
}

///|
test "mcp client response: rejects id mismatch and surfaces json-rpc errors" {
  let mismatch = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(9.0, repr="9"),
    "result": Json::object({}),
  })
  @debug.debug_inspect(
    try? decode_mcp_result(mismatch, expected_id=1),
    content=(
      #|Err(InvalidResponse("unexpected response id"))
    ),
  )
  let remote_error = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "error": Json::object({
      "code": Json::number(-32601.0, repr="-32601"),
      "message": Json::string("method not found"),
    }),
  })
  @debug.debug_inspect(
    try? decode_mcp_result(remote_error, expected_id=1),
    content=(
      #|Err(RemoteError(-32601, "method not found"))
    ),
  )
}
