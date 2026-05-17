///|
test "tool search: case-insensitive substring and glob" {
  let tool = @protocol.mcp_tool_info(
    name="search_code",
    description=Some("Search repository code"),
    input_schema=Json::object({ "query": Json::string("string") }),
  )
  inspect(tool_matches("repo", "github", tool), content="true")
  inspect(tool_matches("GITHUB search", "github", tool), content="true")
  inspect(tool_matches("*query*", "github", tool), content="true")
  inspect(tool_matches("delete", "github", tool), content="false")
}

///|
test "tool search: match json" {
  let tool = @protocol.mcp_tool_info(
    name="list_issues",
    description=Some("List issues"),
    input_schema=Json::object({ "type": Json::string("object") }),
  )
  inspect(
    match_json("github", tool).stringify(),
    content="{\"server\":\"github\",\"tool\":\"list_issues\",\"description\":\"List issues\",\"inputSchema\":{\"type\":\"object\"}}",
  )
}
