///|
test "bench mcp_client initialize/list/call request sequence" (it : @bench.T) {
  let arguments = Json::object({ "q": Json::string("moonbit") })
  it.bench(() => {
    let client = mcp_client(client_name="mcpx", client_version="0.1.0")
    let init = client.initialize_request()
    let initialized = client.initialized_notification()
    let list = client.tools_list_request()
    let call = client.tool_call_request(name="search", arguments~)
    it.keep(
      init.message.stringify().length() +
      initialized.message.stringify().length() +
      list.message.stringify().length() +
      call.message.stringify().length(),
    )
  })
}

///|
test "bench mcp_client decode representative responses" (it : @bench.T) {
  let init_response = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "result": Json::object({
      "protocolVersion": Json::string("2025-03-26"),
      "capabilities": Json::object({}),
      "serverInfo": Json::object({
        "name": Json::string("srv"),
        "version": Json::string("1.0.0"),
      }),
    }),
  })
  let list_response = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(2.0, repr="2"),
    "result": Json::object({
      "tools": Json::array([
        Json::object({
          "name": Json::string("search"),
          "description": Json::string("Search things"),
          "inputSchema": Json::object({ "type": Json::string("object") }),
        }),
        Json::object({
          "name": Json::string("fetch"),
          "inputSchema": Json::object({ "type": Json::string("object") }),
        }),
      ]),
    }),
  })
  let call_response = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(3.0, repr="3"),
    "result": Json::object({
      "content": Json::array([
        Json::object({
          "type": Json::string("text"),
          "text": Json::string("ok"),
        }),
      ]),
    }),
  })
  it.bench(() => {
    let init = decode_mcp_initialize_response(init_response, expected_id=1)
    let tools = decode_mcp_tool_list_response(list_response, expected_id=2)
    let result = decode_mcp_result(call_response, expected_id=3) catch {
      _ => abort("unexpected MCP result error")
    }
    it.keep((init, tools, result))
  })
}

///|
test "bench mcp_client SSE decode ten events" (it : @bench.T) {
  let payload =
    #|event: message
    #|data: {"jsonrpc":"2.0","id":1,"result":{"ok":true}}
    #|
    #|event: message
    #|data: {"jsonrpc":"2.0","id":2,"result":{"ok":true}}
    #|
    #|event: message
    #|data: {"jsonrpc":"2.0","id":3,"result":{"ok":true}}
    #|
    #|event: message
    #|data: {"jsonrpc":"2.0","id":4,"result":{"ok":true}}
    #|
    #|event: message
    #|data: {"jsonrpc":"2.0","id":5,"result":{"ok":true}}
    #|
    #|event: message
    #|data: {"jsonrpc":"2.0","id":6,"result":{"ok":true}}
    #|
    #|event: message
    #|data: {"jsonrpc":"2.0","id":7,"result":{"ok":true}}
    #|
    #|event: message
    #|data: {"jsonrpc":"2.0","id":8,"result":{"ok":true}}
    #|
    #|event: message
    #|data: {"jsonrpc":"2.0","id":9,"result":{"ok":true}}
    #|
    #|event: message
    #|data: {"jsonrpc":"2.0","id":10,"result":{"ok":true}}
    #|
  it.bench(() => it.keep(decode_sse_data(payload).length()))
}
