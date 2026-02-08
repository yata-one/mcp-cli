///|
async test "client: initialize sends initialize + initialized notification" {
  let init_result = Json::object({
    "protocolVersion": Json::string("2025-03-26"),
    "instructions": Json::string("hello"),
    "capabilities": Json::object({}),
    "serverInfo": Json::object({ "name": Json::string("srv") }),
  })
  let init_resp = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": json_int(1),
    "result": init_result,
  })
  let transport = mock_transport([init_resp])
  let c = client(transport)
  c.initialize(client_version="0.1.0")
  inspect(c.get_instructions(), content="Some(\"hello\")")
  let sent = c.transport.sent_messages()
  inspect(sent.length(), content="2")
  let expected_params = Json::object({
    "protocolVersion": Json::string("2025-03-26"),
    "capabilities": Json::object({}),
    "clientInfo": Json::object({
      "name": Json::string("mcp-cli"),
      "version": Json::string("0.1.0"),
    }),
  })
  inspect(
    sent[0] == encode_request(1, "initialize", Some(expected_params)),
    content="true",
  )
  inspect(
    sent[1] == encode_notification("notifications/initialized", None),
    content="true",
  )
}

///|
async test "client: list_tools ignores notifications + decodes tools" {
  let init_resp = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": json_int(1),
    "result": Json::object({
      "protocolVersion": Json::string("2025-03-26"),
      "capabilities": Json::object({}),
      "serverInfo": Json::object({ "name": Json::string("srv") }),
    }),
  })
  let notify = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("notifications/log"),
    "params": Json::object({ "level": Json::string("info") }),
  })
  let tools_result = Json::object({
    "tools": Json::array([
      Json::object({
        "name": Json::string("t1"),
        "description": Json::string("d1"),
        "inputSchema": Json::object({ "type": Json::string("object") }),
      }),
      Json::object({
        "name": Json::string("t2"),
        "inputSchema": Json::object({}),
      }),
    ]),
  })
  let tools_resp = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": json_int(2),
    "result": tools_result,
  })
  let transport = mock_transport([init_resp, notify, tools_resp])
  let c = client(transport)
  c.initialize(client_version="0.1.0")
  let tools = c.list_tools()
  inspect(tools.length(), content="2")
  inspect(tools[0].name, content="t1")
  inspect(tools[0].description, content="Some(\"d1\")")
  inspect(tools[1].name, content="t2")
  inspect(tools[1].description, content="None")
  let sent = c.transport.sent_messages()
  inspect(sent.length(), content="3")
  inspect(
    sent[2] == encode_request(2, "tools/list", Some(Json::object({}))),
    content="true",
  )
}

///|
async test "client: call_tool sends tools/call and returns result json" {
  let init_resp = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": json_int(1),
    "result": Json::object({
      "protocolVersion": Json::string("2025-03-26"),
      "capabilities": Json::object({}),
      "serverInfo": Json::object({ "name": Json::string("srv") }),
    }),
  })
  let call_result = Json::object({
    "content": Json::array([
      Json::object({ "type": Json::string("text"), "text": Json::string("ok") }),
    ]),
  })
  let call_resp = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": json_int(2),
    "result": call_result,
  })
  let transport = mock_transport([init_resp, call_resp])
  let c = client(transport)
  c.initialize(client_version="0.1.0")
  let result = c.call_tool("t1", Json::object({ "x": Json::string("y") }))
  inspect(result == call_result, content="true")
  let sent = c.transport.sent_messages()
  inspect(sent.length(), content="3")
  let expected_params = Json::object({
    "name": Json::string("t1"),
    "arguments": Json::object({ "x": Json::string("y") }),
  })
  inspect(
    sent[2] == encode_request(2, "tools/call", Some(expected_params)),
    content="true",
  )
}

///|
test "tool info json roundtrip" {
  let tool = tool_info(
    "t",
    description="d",
    input_schema=Json::object({ "type": Json::string("object") }),
  )
  let json = tool_info_to_json(tool)
  let decoded = tool_info_from_json(json)
  inspect(decoded.name, content="t")
  inspect(decoded.description, content="Some(\"d\")")
  inspect(
    decoded.input_schema.stringify(indent=2),
    content="{\n  \"type\": \"object\"\n}",
  )
}
