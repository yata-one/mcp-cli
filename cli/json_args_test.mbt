///|
test "parse_json_args: empty -> {}" {
  inspect(parse_json_args("").stringify(indent=2), content="{}")
  inspect(parse_json_args("   \n").stringify(indent=2), content="{}")
}

///|
test "parse_json_args: object ok" {
  let json = parse_json_args("{\"x\": 1}")
  inspect(json.stringify(indent=2), content="{\n  \"x\": 1\n}")
}

///|
test "parse_json_args: rejects non-object" {
  let r : Result[Json, JsonArgsError] = try? parse_json_args("[1,2]")
  inspect(r, content="Err(ArgsMustBeObject)")
}
