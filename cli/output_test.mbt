///|
test "format_server_list" {
  let servers = [
    server_view(
      "s1",
      [
        tool_view("t1", description="d1", input_schema=Json::object({})),
        tool_view("t2", input_schema=Json::object({})),
      ],
      instructions="hello\nworld",
    ),
    server_view("s2", [
      tool_view("x", description="dx", input_schema=Json::object({})),
    ]),
  ]
  let out = format_server_list(servers)
  inspect(
    out,
    content=(
      #|s1
      #|  Instructions: hello
      #|  • t1 - d1
      #|  • t2
      #|
      #|s2
      #|  • x - dx
    ),
  )
}

///|
test "format_search_results" {
  let results = [
    (
      "fs",
      tool_view(
        "read_file",
        description="read\n\nArgs:\n  path: a file",
        input_schema=Json::object({
          "type": Json::string("object"),
          "properties": Json::object({
            "path": Json::object({
              "type": Json::string("string"),
              "description": Json::string("p"),
            }),
          }),
          "required": Json::array([Json::string("path")]),
        }),
      ),
    ),
    ("fs", tool_view("write_file", input_schema=Json::object({}))),
  ]
  inspect(
    format_search_results(results),
    content=(
      #|List grep results (<server>/<tool> in detail):
      #|
      #|fs/read_file: read
      #|
      #|Args:
      #|  path: a file
      #|
      #|fs/write_file
    ),
  )
}

///|
test "format_tool_schema" {
  let tool = tool_view(
    "t",
    description="desc",
    input_schema=Json::object({ "type": Json::string("object") }),
  )
  inspect(
    format_tool_schema("s", tool),
    content=(
      #|Tool: t
      #|Server: s
      #|
      #|Description:
      #|  desc
      #|
      #|Input Schema:
      #|{
      #|  "type": "object"
      #|}
    ),
  )
}

///|
test "format_tool_result: extracts text content (fallback json)" {
  let result = Json::object({
    "content": Json::array([
      Json::object({ "type": Json::string("text"), "text": Json::string("a") }),
      Json::object({ "type": Json::string("image"), "url": Json::string("x") }),
      Json::object({ "type": Json::string("text"), "text": Json::string("b") }),
    ]),
  })
  inspect(format_tool_result(result), content="a\nb")
  let no_text = Json::object({
    "content": Json::array([
      Json::object({ "type": Json::string("image"), "url": Json::string("x") }),
    ]),
  })
  inspect(
    format_tool_result(no_text),
    content=(
      #|{
      #|  "content": [
      #|    {
      #|      "type": "image",
      #|      "url": "x"
      #|    }
      #|  ]
      #|}
    ),
  )
}

///|
test "format_server_details" {
  let cfg = parse_jsonc(
    (
      #|{
      #|  "mcpServers": {
      #|    "s": { "command": "node", "args": ["a"] }
      #|  }
      #|}
    ),
  )
  let server = cfg.servers.get("s").unwrap()
  let tool = tool_view(
    "t",
    description="d",
    input_schema=Json::object({
      "properties": Json::object({
        "x": Json::object({
          "type": Json::string("string"),
          "description": Json::string("xd"),
        }),
      }),
      "required": Json::array([Json::string("x")]),
    }),
  )
  inspect(
    format_server_details("s", server, [tool], Some("hi")),
    content=(
      #|Server: s
      #|Transport: stdio
      #|Command: node a
      #|
      #|Instructions:
      #|  hi
      #|
      #|Tools (1):
      #|  t
      #|    d
      #|    Parameters:
      #|      • x (string, required) - xd
    ),
  )
}
