///|
test "matches_pattern: supports * and ? (ascii case-insensitive)" {
  inspect(matches_pattern("read_file", "read_*"), content="true")
  inspect(matches_pattern("READ_FILE", "read_*"), content="true")
  inspect(matches_pattern("tool1", "tool?"), content="true")
  inspect(matches_pattern("tool10", "tool?"), content="false")
  inspect(matches_pattern("abc", "*b*"), content="true")
  inspect(matches_pattern("abc", "*d*"), content="false")
}

///|
test "is_tool_allowed: disabledTools overrides allowedTools" {
  let cfg = parse_jsonc(
    (
      #|{
      #|  "mcpServers": {
      #|    "s": {
      #|      "command": "x",
      #|      "allowedTools": ["read_*"],
      #|      "disabledTools": ["read_secret"]
      #|    }
      #|  }
      #|}
    ),
  )
  let s = cfg.servers.get("s").unwrap()
  inspect(is_tool_allowed("read_file", s), content="true")
  inspect(is_tool_allowed("read_secret", s), content="false")
  inspect(is_tool_allowed("write_file", s), content="false")
}
