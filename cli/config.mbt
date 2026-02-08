///|
suberror ConfigError {
  ConfigNotFound
  ReadFailed(String, String)
  InvalidJsonc
  InvalidJson(String)
  InvalidRoot
  MissingField(String)
  InvalidField(String)
  InvalidServer(String, String)
  MissingEnvVar(String)
  InvalidEnvVarSyntax(String)
}

///|
pub impl Show for ConfigError with output(self, logger) {
  match self {
    ConfigNotFound => logger.write_string("ConfigNotFound")
    ReadFailed(path, msg) => {
      logger.write_string("ReadFailed(\"")
      logger.write_string(path)
      logger.write_string("\", \"")
      logger.write_string(msg)
      logger.write_string("\")")
    }
    InvalidJsonc => logger.write_string("InvalidJsonc")
    InvalidJson(msg) => {
      logger.write_string("InvalidJson(\"")
      logger.write_string(msg)
      logger.write_string("\")")
    }
    InvalidRoot => logger.write_string("InvalidRoot")
    MissingField(key) => {
      logger.write_string("MissingField(\"")
      logger.write_string(key)
      logger.write_string("\")")
    }
    InvalidField(key) => {
      logger.write_string("InvalidField(\"")
      logger.write_string(key)
      logger.write_string("\")")
    }
    InvalidServer(name, msg) => {
      logger.write_string("InvalidServer(\"")
      logger.write_string(name)
      logger.write_string("\", \"")
      logger.write_string(msg)
      logger.write_string("\")")
    }
    MissingEnvVar(name) => {
      logger.write_string("MissingEnvVar(\"")
      logger.write_string(name)
      logger.write_string("\")")
    }
    InvalidEnvVarSyntax(raw) => {
      logger.write_string("InvalidEnvVarSyntax(\"")
      logger.write_string(raw)
      logger.write_string("\")")
    }
  }
}

///|
pub struct Config {
  servers : Map[String, ServerConfig]
} derive(Show)

///|
pub struct ServerConfig {
  transport : Transport
  allowed_tools : Array[String]
  disabled_tools : Array[String]
} derive(Show)

///|
pub enum Transport {
  Stdio(String, Array[String], Map[String, String], String?)
  Http(String, Map[String, String])
} derive(Show)

///|
pub fn empty() -> Config {
  { servers: Map::new() }
}

///|
pub fn merge(base : Config, overlay : Config) -> Config {
  let merged = base.servers.copy()
  for name, server in overlay.servers {
    merged[name] = server
  }
  { servers: merged }
}

///|
pub fn parse_jsonc(input : String) -> Config raise ConfigError {
  let normalized = normalize(input) catch {
    _ => raise ConfigError::InvalidJsonc
  }
  let json = @json.parse(normalized) catch {
    err => raise ConfigError::InvalidJson(err.to_string())
  }
  decode_config(json)
}

///|
pub fn resolve_env(
  config : Config,
  env~ : Map[String, String],
  strict? : Bool = true,
) -> Config raise ConfigError {
  let out = Map::new(capacity=config.servers.length())
  for name, server in config.servers {
    out[name] = resolve_env_server(server, env, strict)
  }
  { servers: out }
}

///|
pub fn load(config_path? : String) -> Config raise ConfigError {
  let env = @sys.get_env_vars()
  let strict = is_strict_env(env)
  let paths = match config_path {
    Some(p) => [p]
    None => default_config_paths()
  }
  let mut found_any = false
  let mut acc = empty()
  for p in paths {
    if @fs.path_exists(p) {
      found_any = true
      let content = @fs.read_file_to_string(p) catch {
        err => raise ConfigError::ReadFailed(p, err.to_string())
      }
      let parsed = parse_jsonc(content)
      let resolved = resolve_env(parsed, env~, strict~)
      acc = merge(acc, resolved)
    }
  }
  if found_any {
    acc
  } else {
    raise ConfigError::ConfigNotFound
  }
}

///|
pub fn default_config_paths() -> Array[String] {
  let project_root = find_project_root()
  let paths = []
  match @sys.get_env_var("HOME") {
    Some(home) => {
      for p in skill_config_paths(home_skills_dir(home)) {
        paths.push(p)
      }
      paths.push(home_config_path(home))
      paths.push(home_config_path_jsonc(home))
    }
    None => ()
  }
  for p in skill_config_paths(project_skills_dir(project_root)) {
    paths.push(p)
  }
  paths.push(project_config_path(project_root))
  paths.push(project_config_path_jsonc(project_root))
  paths
}

///|
fn home_config_path(home : String) -> String {
  @path.Path(home)
  .join(@path.Path(".agents"))
  .join(@path.Path("mcp-cli.json"))
  .to_string()
}

///|
fn home_config_path_jsonc(home : String) -> String {
  @path.Path(home)
  .join(@path.Path(".agents"))
  .join(@path.Path("mcp-cli.jsonc"))
  .to_string()
}

///|
fn project_config_path(project_root : String) -> String {
  @path.Path(project_root)
  .join(@path.Path(".agents"))
  .join(@path.Path("mcp-cli.json"))
  .to_string()
}

///|
fn project_config_path_jsonc(project_root : String) -> String {
  @path.Path(project_root)
  .join(@path.Path(".agents"))
  .join(@path.Path("mcp-cli.jsonc"))
  .to_string()
}

///|
pub fn skill_config_paths(skills_dir : String) -> Array[String] {
  if !@fs.path_exists(skills_dir) {
    return []
  }
  if !(@fs.is_dir(skills_dir) catch { _ => false }) {
    return []
  }
  let entries = @fs.read_dir(skills_dir) catch { _ => return [] }
  entries.sort()
  let paths = []
  for name in entries {
    let base = @path.Path(skills_dir).join(@path.Path(name))
    let jsonc = base.join(@path.Path("mcp-cli.jsonc")).to_string()
    if (@fs.is_file(jsonc) catch { _ => false }) {
      paths.push(jsonc)
    } else {
      let json = base.join(@path.Path("mcp-cli.json")).to_string()
      if (@fs.is_file(json) catch { _ => false }) {
        paths.push(json)
      }
    }
  }
  paths
}

///|
fn home_skills_dir(home : String) -> String {
  @path.Path(home)
  .join(@path.Path(".agents"))
  .join(@path.Path("skills"))
  .to_string()
}

///|
fn project_skills_dir(project_root : String) -> String {
  @path.Path(project_root)
  .join(@path.Path(".agents"))
  .join(@path.Path("skills"))
  .to_string()
}

///|
fn find_project_root() -> String {
  let start = @path.Path(".").resolve()
  loop start {
    current =>
      if is_git_root(current) {
        current.to_string()
      } else {
        let parent = current.dirname()
        if parent == current {
          current.to_string()
        } else {
          continue parent
        }
      }
  }
}

///|
fn is_git_root(dir : @path.Path) -> Bool {
  let git_dir = dir.join(@path.Path(".git")).to_string()
  @fs.path_exists(git_dir) && (@fs.is_dir(git_dir) catch { _ => false })
}

///|
fn is_strict_env(env : Map[String, String]) -> Bool {
  match env.get("MCP_STRICT_ENV") {
    Some("false") | Some("0") => false
    _ => true
  }
}

///|
fn decode_config(json : Json) -> Config raise ConfigError {
  match json {
    Object(root) =>
      match root.get("mcpServers") {
        Some(Object(servers_obj)) => decode_servers(servers_obj)
        Some(_) => raise ConfigError::InvalidField("mcpServers")
        None => raise ConfigError::MissingField("mcpServers")
      }
    _ => raise ConfigError::InvalidRoot
  }
}

///|
fn decode_servers(servers_obj : Map[String, Json]) -> Config raise ConfigError {
  let servers = Map::new(capacity=servers_obj.length())
  for name, def in servers_obj {
    servers[name] = decode_server(name, def)
  }
  { servers, }
}

///|
fn decode_server(name : String, def : Json) -> ServerConfig raise ConfigError {
  let obj = match def {
    Object(obj) => obj
    _ =>
      raise ConfigError::InvalidServer(
        name, "server definition must be an object",
      )
  }
  let allowed_tools = decode_string_array_or_default(obj, "allowedTools", ["*"])
  let disabled_tools = decode_string_array_or_default(obj, "disabledTools", [])
  let command = obj.get("command")
  let url = obj.get("url")
  match (command, url) {
    (Some(String(cmd)), None) => {
      let args = decode_string_array_or_default(obj, "args", [])
      let env = decode_string_map_or_default(obj, "env", Map::new())
      let cwd = decode_string_opt(obj, "cwd")
      {
        transport: Transport::Stdio(cmd, args, env, cwd),
        allowed_tools,
        disabled_tools,
      }
    }
    (None, Some(String(url))) => {
      let headers = decode_string_map_or_default(obj, "headers", Map::new())
      {
        transport: Transport::Http(url, headers),
        allowed_tools,
        disabled_tools,
      }
    }
    (Some(_), Some(_)) =>
      raise ConfigError::InvalidServer(name, "both 'command' and 'url' are set")
    (Some(_), None) =>
      raise ConfigError::InvalidServer(name, "'command' must be a string")
    (None, Some(_)) =>
      raise ConfigError::InvalidServer(name, "'url' must be a string")
    (None, None) =>
      raise ConfigError::InvalidServer(
        name, "missing 'command' (stdio) or 'url' (http)",
      )
  }
}

///|
pub fn decode_server_config(
  name : String,
  def : Json,
) -> ServerConfig raise ConfigError {
  decode_server(name, def)
}

///|
pub fn encode_server_config(server : ServerConfig) -> Json {
  let obj = Map::new()
  match server.transport {
    Transport::Stdio(command, args, env, cwd) => {
      obj["command"] = Json::string(command)
      if !args.is_empty() {
        obj["args"] = Json::array(args.map(Json::string))
      }
      if !env.is_empty() {
        let env_obj = Map::new(capacity=env.length())
        for k, v in env {
          env_obj[k] = Json::string(v)
        }
        obj["env"] = Json::object(env_obj)
      }
      match cwd {
        None => ()
        Some(dir) => obj["cwd"] = Json::string(dir)
      }
    }
    Transport::Http(url, headers) => {
      obj["url"] = Json::string(url)
      if !headers.is_empty() {
        let h_obj = Map::new(capacity=headers.length())
        for k, v in headers {
          h_obj[k] = Json::string(v)
        }
        obj["headers"] = Json::object(h_obj)
      }
    }
  }
  if server.allowed_tools != ["*"] {
    obj["allowedTools"] = Json::array(server.allowed_tools.map(Json::string))
  }
  if !server.disabled_tools.is_empty() {
    obj["disabledTools"] = Json::array(server.disabled_tools.map(Json::string))
  }
  Json::object(obj)
}

///|
fn decode_string_opt(
  obj : Map[String, Json],
  key : String,
) -> String? raise ConfigError {
  match obj.get(key) {
    None | Some(Null) => None
    Some(String(s)) => Some(s)
    Some(_) => raise ConfigError::InvalidField(key)
  }
}

///|
fn decode_string_array_or_default(
  obj : Map[String, Json],
  key : String,
  default : Array[String],
) -> Array[String] raise ConfigError {
  match obj.get(key) {
    None | Some(Null) => default
    Some(Array(items)) => items.map(item => decode_string(item, key))
    Some(_) => raise ConfigError::InvalidField(key)
  }
}

///|
fn decode_string_map_or_default(
  obj : Map[String, Json],
  key : String,
  default : Map[String, String],
) -> Map[String, String] raise ConfigError {
  match obj.get(key) {
    None | Some(Null) => default
    Some(Object(m)) => {
      let out = Map::new(capacity=m.length())
      for k, v in m {
        out[k] = decode_string(v, key)
      }
      out
    }
    Some(_) => raise ConfigError::InvalidField(key)
  }
}

///|
fn decode_string(val : Json, context_key : String) -> String raise ConfigError {
  match val {
    String(s) => s
    _ => raise ConfigError::InvalidField(context_key)
  }
}

///|
fn resolve_env_server(
  server : ServerConfig,
  env : Map[String, String],
  strict : Bool,
) -> ServerConfig raise ConfigError {
  let transport = match server.transport {
    Transport::Stdio(command, args, envs, cwd) => {
      let new_command = envsubst(command, env, strict)
      let new_args = args.map(a => envsubst(a, env, strict))
      let new_envs = envsubst_map(envs, env, strict)
      let new_cwd = cwd.map(c => envsubst(c, env, strict))
      Transport::Stdio(new_command, new_args, new_envs, new_cwd)
    }
    Transport::Http(url, headers) => {
      let new_url = envsubst(url, env, strict)
      let new_headers = envsubst_map(headers, env, strict)
      Transport::Http(new_url, new_headers)
    }
  }
  let new_allowed = server.allowed_tools.map(t => envsubst(t, env, strict))
  let new_disabled = server.disabled_tools.map(t => envsubst(t, env, strict))
  { transport, allowed_tools: new_allowed, disabled_tools: new_disabled }
}

///|
fn envsubst(
  input : String,
  env : Map[String, String],
  strict : Bool,
) -> String raise ConfigError {
  let view = input.to_string_view()
  let sb = StringBuilder::new(size_hint=view.length())
  for i = 0; i < view.length(); {
    let c = view.get_char(i).unwrap()
    if c == '$' && view.get_char(i + 1) == Some('{') {
      let close = find_closing_brace(view, i + 2)
      match close {
        None => raise ConfigError::InvalidEnvVarSyntax(input)
        Some(j) => {
          let name = view.view(start_offset=i + 2, end_offset=j).to_string()
          if name.is_empty() {
            raise ConfigError::InvalidEnvVarSyntax(input)
          }
          let value = match env.get(name) {
            Some(v) => v
            None =>
              if strict {
                raise ConfigError::MissingEnvVar(name)
              } else {
                ""
              }
          }
          sb.write_string(value)
          continue j + 1
        }
      }
    } else {
      sb.write_char(c)
      continue i + 1
    }
  } else {
    sb.to_string()
  }
}

///|
fn find_closing_brace(view : StringView, start : Int) -> Int? {
  for i = start; i < view.length(); i = i + 1 {
    if view.get_char(i) == Some('}') {
      break Some(i)
    }
  } else {
    None
  }
}

///|
fn envsubst_map(
  input : Map[String, String],
  env : Map[String, String],
  strict : Bool,
) -> Map[String, String] raise ConfigError {
  let out = Map::new(capacity=input.length())
  for k, v in input {
    out[k] = envsubst(v, env, strict)
  }
  out
}
