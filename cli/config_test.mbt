///|
test "parse_jsonc: stdio server" {
  let input =
    #|{
    #|  // comment
    #|  "mcpServers": {
    #|    "local": {
    #|      "command": "node",
    #|      "args": ["server.js",],
    #|      "env": { "API_KEY": "${API_KEY}", },
    #|      "cwd": "/tmp",
    #|      "allowedTools": ["read_*",],
    #|      "disabledTools": ["delete_*"]
    #|    },
    #|  },
    #|}
  let cfg = parse_jsonc(input)
  let local_server = cfg.servers.get("local").unwrap()
  match local_server.transport {
    Transport::Stdio(command, args, env, cwd) => {
      inspect(command, content="node")
      inspect(args, content="[\"server.js\"]")
      inspect(env.get("API_KEY"), content="Some(\"${API_KEY}\")")
      inspect(cwd, content="Some(\"/tmp\")")
    }
    _ => fail("expected stdio transport")
  }
  inspect(local_server.allowed_tools, content="[\"read_*\"]")
  inspect(local_server.disabled_tools, content="[\"delete_*\"]")
}

///|
test "resolve_env: substitutes ${VAR} (strict=true)" {
  let cfg = parse_jsonc(
    (
      #|{
      #|  "mcpServers": {
      #|    "s": { "command": "echo", "env": { "X": "${X}" } }
      #|  }
      #|}
    ),
  )
  let env = { "X": "ok" }
  let resolved = resolve_env(cfg, env~, strict=true)
  match resolved.servers.get("s").unwrap().transport {
    Transport::Stdio(_, _, env2, _) =>
      inspect(env2.get("X"), content="Some(\"ok\")")
    _ => fail("expected stdio transport")
  }
}

///|
test "resolve_env: missing var raises when strict=true" {
  let cfg = parse_jsonc(
    (
      #|{
      #|  "mcpServers": {
      #|    "s": { "command": "echo", "env": { "X": "${X}" } }
      #|  }
      #|}
    ),
  )
  let result : Result[Config, ConfigError] = try? resolve_env(
    cfg,
    env={},
    strict=true,
  )
  inspect(result, content="Err(MissingEnvVar(\"X\"))")
}

///|
test "merge: project overrides home by server name" {
  let home = parse_jsonc(
    (
      #|{
      #|  "mcpServers": { "s": { "command": "home" } }
      #|}
    ),
  )
  let project = parse_jsonc(
    (
      #|{
      #|  "mcpServers": { "s": { "command": "project" } }
      #|}
    ),
  )
  let merged = merge(home, project)
  match merged.servers.get("s").unwrap().transport {
    Transport::Stdio(command, _, _, _) => inspect(command, content="project")
    _ => fail("expected stdio transport")
  }
}

///|
test "encode/decode server config: stdio roundtrip" {
  let cfg = parse_jsonc(
    (
      #|{
      #|  "mcpServers": {
      #|    "s": {
      #|      "command": "node",
      #|      "args": ["a"],
      #|      "env": { "X": "1" },
      #|      "cwd": "/tmp",
      #|      "allowedTools": ["*"],
      #|      "disabledTools": ["x"]
      #|    }
      #|  }
      #|}
    ),
  )
  let s = cfg.servers.get("s").unwrap()
  let json = encode_server_config(s)
  let decoded = decode_server_config("d", json)
  match decoded.transport {
    Transport::Stdio(cmd, args, env, cwd) => {
      inspect(cmd, content="node")
      inspect(args, content="[\"a\"]")
      inspect(env.get("X"), content="Some(\"1\")")
      inspect(cwd, content="Some(\"/tmp\")")
    }
    _ => fail("expected stdio transport")
  }
  inspect(decoded.allowed_tools, content="[\"*\"]")
  inspect(decoded.disabled_tools, content="[\"x\"]")
}

///|
test "encode/decode server config: http roundtrip" {
  let cfg = parse_jsonc(
    (
      #|{
      #|  "mcpServers": {
      #|    "s": {
      #|      "url": "http://example.com/mcp",
      #|      "headers": { "Authorization": "Bearer t" }
      #|    }
      #|  }
      #|}
    ),
  )
  let s = cfg.servers.get("s").unwrap()
  let json = encode_server_config(s)
  let decoded = decode_server_config("d", json)
  match decoded.transport {
    Transport::Http(url, headers) => {
      inspect(url, content="http://example.com/mcp")
      inspect(headers.get("Authorization"), content="Some(\"Bearer t\")")
    }
    _ => fail("expected http transport")
  }
  inspect(decoded.allowed_tools, content="[\"*\"]")
  inspect(decoded.disabled_tools, content="[]")
}

///|
fn join(base : String, child : String) -> String {
  @path.Path(base).join(@path.Path(child)).to_string()
}

///|
fn mkdir(path : String) -> Unit {
  @fs.create_dir(path) catch {
    _ => ()
  }
}

///|
fn write(path : String, content : String) -> Unit {
  @fs.write_string_to_file(path, content) catch {
    _ => ()
  }
}

///|
test "skill_config_paths: missing directory => empty" {
  let paths = skill_config_paths("/tmp/mcp-cli-skill-config-missing-dir")
  inspect(paths, content="[]")
}

///|
test "skill_config_paths: sorts skills + prefers jsonc" {
  let root = join("_build", "skill_config_paths_test")
  mkdir(root)
  let skills = join(root, "skills")
  mkdir(skills)
  let a = join(skills, "aaa")
  mkdir(a)
  write(
    join(a, "mcp-cli.json"),
    "{ \"mcpServers\": { \"a\": { \"url\": \"x\" } } }",
  )
  let b = join(skills, "bbb")
  mkdir(b)
  write(
    join(b, "mcp-cli.jsonc"),
    "{ /* jsonc */ \"mcpServers\": { \"b\": { \"url\": \"x\" } } }",
  )
  let c = join(skills, "ccc")
  mkdir(c)
  let d = join(skills, "ddd")
  mkdir(d)
  write(
    join(d, "mcp-cli.json"),
    "{ \"mcpServers\": { \"d\": { \"url\": \"x\" } } }",
  )
  write(
    join(d, "mcp-cli.jsonc"),
    "{ // jsonc wins\n\"mcpServers\": { \"d\": { \"url\": \"y\" } } }",
  )
  let paths = skill_config_paths(skills)
  let skill_names = paths.map(p => @path.Path(p).dirname().basename())
  let file_names = paths.map(p => @path.Path(p).basename())
  inspect(skill_names, content="[\"aaa\", \"bbb\", \"ddd\"]")
  inspect(
    file_names,
    content="[\"mcp-cli.json\", \"mcp-cli.jsonc\", \"mcp-cli.jsonc\"]",
  )
}
