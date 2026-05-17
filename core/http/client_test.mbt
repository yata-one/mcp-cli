///|
async test "core http: list tools uses injected fetch linearly" {
  let seen : Array[String] = []
  let tools = list_tools(
    req => {
      seen.push(req.body)
      if seen.length() == 1 {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{},"serverInfo":{"name":"mock","version":"1"}}}
          ),
        )
      } else if seen.length() == 2 {
        http_response(status_code=202, content_type=None, body="{}")
      } else {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"search","description":"Search","inputSchema":{"type":"object"}}]}}
          ),
        )
      }
    },
    http_endpoint(url="https://mcp.example/mcp"),
  )
  inspect(tools.length(), content="1")
  inspect(tools[0].name, content="search")
  inspect(seen.length(), content="3")
}

///|
async test "core http: call tool uses injected fetch linearly" {
  let seen : Array[String] = []
  let result = call_tool(
    req => {
      seen.push(req.body)
      if seen.length() == 1 {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{},"serverInfo":{"name":"mock","version":"1"}}}
          ),
        )
      } else if seen.length() == 2 {
        http_response(status_code=202, content_type=None, body="{}")
      } else {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"ok"}]}}
          ),
        )
      }
    },
    http_endpoint(url="https://mcp.example/mcp"),
    tool_name="search",
    arguments=Json::object({ "q": Json::string("moonbit") }),
  )
  inspect(
    result.stringify(),
    content=(
      #|{"content":[{"type":"text","text":"ok"}]}
    ),
  )
  inspect(seen.length(), content="3")
}
