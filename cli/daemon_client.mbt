///|
/// CLI-side daemon client: ensure daemon is running and proxy requests.

///|
pub suberror DaemonError {
  Unavailable
  ConnectFailed(String)
  InvalidResponse(String)
  RemoteError(String)
  SpawnFailed(String)
  StartTimeout
} derive(Show)

///|
pub async fn daemon_list_tools(
  settings : Settings,
  server : ServerConfig,
) -> (Array[ToolInfo], String?) {
  let port = ensure_running(settings)
  let key = encode_server_config(server).stringify()
  let req = Json::object({
    "op": Json::string("list_tools"),
    "key": Json::string(key),
    "server": encode_server_config(server),
  })
  let resp = request(port, req)
  decode_list_tools_response(resp)
}

///|
pub async fn daemon_call_tool(
  settings : Settings,
  server : ServerConfig,
  tool_name : String,
  args_json : Json,
) -> Json {
  let port = ensure_running(settings)
  let key = encode_server_config(server).stringify()
  let req = Json::object({
    "op": Json::string("call_tool"),
    "key": Json::string(key),
    "server": encode_server_config(server),
    "tool": Json::string(tool_name),
    "args": args_json,
  })
  let resp = request(port, req)
  decode_call_tool_response(resp)
}

///|
async fn ensure_running(settings : Settings) -> Int {
  if settings.no_daemon {
    raise DaemonError::Unavailable
  }
  let path = state_path()
  match read_port(path) {
    Some(port) => if ping(port) { port } else { start_daemon(path) }
    None => start_daemon(path)
  }
}

///|
async fn start_daemon(path : String) -> Int {
  let exe = match @sys.get_cli_args().get(0) {
    None => "mcp-cli"
    Some(s) => s
  }
  ignore(
    @process.spawn_orphan(exe, ["--daemon"]) catch {
      err => raise DaemonError::SpawnFailed(err.to_string())
    },
  )
  let deadline = @async.now() + 5000L
  for {
    if @async.now() >= deadline {
      raise DaemonError::StartTimeout
    }
    match read_port(path) {
      Some(port) if ping(port) => break port
      _ => @async.sleep(50)
    }
  }
}

///|
async fn ping(port : Int) -> Bool {
  let req = Json::object({ "op": Json::string("ping") })
  let result : Result[Json, _] = try? request(port, req)
  match result {
    Ok(resp) =>
      match resp {
        Object(o) =>
          match o.get("ok") {
            Some(True) => true
            _ => false
          }
        _ => false
      }
    Err(_) => false
  }
}

///|
async fn request(port : Int, req : Json) -> Json raise DaemonError {
  let addr = @socket.Addr::parse("127.0.0.1:\{port}") catch {
    err => raise DaemonError::ConnectFailed(err.to_string())
  }
  let conn = @socket.Tcp::connect(addr) catch {
    err => raise DaemonError::ConnectFailed(err.to_string())
  }
  conn.write(req.stringify() + "\n") catch {
    err => raise DaemonError::ConnectFailed(err.to_string())
  }
  let line = conn.read_until("\n") catch {
    err => raise DaemonError::ConnectFailed(err.to_string())
  }
  conn.close()
  match line {
    None => raise DaemonError::InvalidResponse("empty response")
    Some(text) =>
      @json.parse(text) catch {
        err => raise DaemonError::InvalidResponse(err.to_string())
      }
  }
}

///|
fn decode_list_tools_response(
  resp : Json,
) -> (Array[ToolInfo], String?) raise DaemonError {
  let obj = match resp {
    Object(o) => o
    _ => raise DaemonError::InvalidResponse("response must be an object")
  }
  match obj.get("ok") {
    Some(True) => {
      let result = obj.get("result").unwrap_or(Json::object({}))
      match result {
        Object(r) => {
          let tools_json = match r.get("tools") {
            Some(Array(arr)) => arr
            _ => []
          }
          let tools = []
          for j in tools_json {
            let tool = tool_info_from_json(j) catch {
              _ => raise DaemonError::InvalidResponse("invalid tools[]")
            }
            tools.push(tool)
          }
          let instructions = match r.get("instructions") {
            Some(String(s)) => Some(s)
            _ => None
          }
          (tools, instructions)
        }
        _ => ([], None)
      }
    }
    Some(False) => {
      let msg = match obj.get("error") {
        Some(String(s)) => s
        _ => "daemon error"
      }
      raise DaemonError::RemoteError(msg)
    }
    _ => raise DaemonError::InvalidResponse("missing ok field")
  }
}

///|
fn decode_call_tool_response(resp : Json) -> Json raise DaemonError {
  let obj = match resp {
    Object(o) => o
    _ => raise DaemonError::InvalidResponse("response must be an object")
  }
  match obj.get("ok") {
    Some(True) => obj.get("result").unwrap_or(Json::object({}))
    Some(False) => {
      let msg = match obj.get("error") {
        Some(String(s)) => s
        _ => "daemon error"
      }
      raise DaemonError::RemoteError(msg)
    }
    _ => raise DaemonError::InvalidResponse("missing ok field")
  }
}
