///|
test "parse_args: default is list" {
  let args = parse_args([])
  inspect(args.command, content="List")
}

///|
test "parse_args: -d is no longer supported" {
  let r : Result[ParsedArgs, _] = try? parse_args(["-d"])
  inspect(r, content="Err(UnknownOption(\"-d\"))")
}

///|
test "parse_args: info supports server/tool" {
  let a1 = parse_args(["info", "srv"])
  inspect(a1.command, content="Info(\"srv\", None)")
  let a2 = parse_args(["info", "srv/tool"])
  inspect(a2.command, content="Info(\"srv\", Some(\"tool\"))")
}

///|
test "parse_args: call supports space + json args" {
  let a = parse_args(["call", "srv", "tool", "{ \"x\": 1 }"])
  inspect(
    a.command,
    content="Call(\"srv\", \"tool\", Some(\"{ \\\"x\\\": 1 }\"))",
  )
}

///|
test "parse_args: --daemon" {
  let a = parse_args(["--daemon"])
  inspect(a.command, content="Daemon")
}

///|
test "parse_args: unknown subcommand aliases error" {
  let r : Result[ParsedArgs, _] = try? parse_args(["list"])
  inspect(r, content="Err(UnknownSubcommand(\"list\"))")
}

///|
test "parse_args: slash form without subcommand is ambiguous" {
  let r1 : Result[ParsedArgs, _] = try? parse_args(["srv/tool"])
  inspect(r1, content="Err(AmbiguousCommand(\"srv\", \"tool\", false))")
  let r2 : Result[ParsedArgs, _] = try? parse_args(["srv/tool", "{}"])
  inspect(r2, content="Err(AmbiguousCommand(\"srv\", \"tool\", true))")
}

///|
test "parse_args: space form server tool is ambiguous (require subcommand)" {
  let r : Result[ParsedArgs, _] = try? parse_args(["srv", "tool"])
  inspect(r, content="Err(AmbiguousCommand(\"srv\", \"tool\", false))")
}

///|
test "parse_args: space form server + json is treated as info" {
  let a = parse_args(["srv", "{ \"x\": 1 }"])
  inspect(a.command, content="Info(\"srv\", None)")
}
