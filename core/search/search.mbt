///|
pub fn tool_matches(
  pattern : String,
  server_name : String,
  tool : @protocol.McpToolInfo,
) -> Bool {
  let needle = pattern.to_lower()
  let haystack = (server_name +
  " " +
  tool.name +
  " " +
  tool.description.unwrap_or("") +
  " " +
  tool.input_schema.stringify()).to_lower()
  if needle.contains("*") || needle.contains("?") {
    @config.glob_match(needle, haystack)
  } else {
    haystack.contains(needle)
  }
}

///|
pub fn match_json(server_name : String, tool : @protocol.McpToolInfo) -> Json {
  let obj = Map([])
  obj["server"] = Json::string(server_name)
  obj["tool"] = Json::string(tool.name)
  match tool.description {
    Some(value) => obj["description"] = Json::string(value)
    None => ()
  }
  obj["inputSchema"] = tool.input_schema
  Json::object(obj)
}
