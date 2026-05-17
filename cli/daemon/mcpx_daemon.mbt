///|
pub suberror McpxDaemonError {
  Unavailable
  ConnectFailed(String)
  InvalidResponse(String)
  RemoteError(String)
  Stdio(String)
} derive(Debug)

///|
priv struct DaemonEntry {
  client : @mcp_stdio.StdioMcpClient
  mutex : @async.Semaphore
  idle_timeout_ms : Int?
  mut last_used_ms : Int64
}

///|
priv struct DaemonPool {
  entries : Map[String, Ref[DaemonEntry]]
  lock : @async.Semaphore
}

///|
fn daemon_pool() -> DaemonPool {
  { entries: Map([]), lock: @async.Semaphore(1) }
}

///|
pub fn mcpx_daemon_state_path(
  home~ : String,
  config_home? : String? = None,
) -> String {
  @app_paths.mcpx_app_paths(home, config_home~).config_dir + "/daemon.json"
}

///|
pub fn read_mcpx_daemon_port(
  home~ : String,
  config_home? : String? = None,
) -> Int? {
  let path = mcpx_daemon_state_path(home~, config_home~)
  if !@fs.path_exists(path) {
    return None
  }
  let text = @fs.read_file_to_string(path) catch { _ => return None }
  let json = @json.parse(text) catch { _ => return None }
  match json {
    Object(obj) =>
      match obj.get("port") {
        Some(Number(value, ..)) if value.trunc() == value =>
          Some(value.to_int())
        _ => None
      }
    _ => None
  }
}

///|
pub async fn run_mcpx_daemon_foreground(
  home~ : String,
  config_home? : String? = None,
) -> Unit {
  @async.with_task_group(group => {
    let pool = daemon_pool()
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr.port()
    write_daemon_state(home~, config_home~, port~)
    defer remove_daemon_state(home~, config_home~)
    server.run_forever(allow_failure=true, (conn, _) => {
      handle_conn(conn, group, pool, server)
    })
  }) catch {
    _ => ()
  }
}

///|
pub async fn daemon_ping(home~ : String, config_home? : String? = None) -> Bool {
  let req = Json::object({ "op": Json::string("ping") })
  let result : Result[Json, _] = try? request(home~, config_home~, req)
  match result {
    Ok(Object(obj)) => obj.get("ok") == Some(Json::boolean(true))
    _ => false
  }
}

///|
pub async fn ensure_mcpx_daemon_running(
  home~ : String,
  config_home? : String? = None,
) -> Bool raise McpxDaemonError {
  if (daemon_ping(home~, config_home~) catch { _ => false }) {
    return true
  }
  start_daemon_process()
  for _ in 0..<100 {
    if (daemon_ping(home~, config_home~) catch { _ => false }) {
      return true
    }
    @async.sleep(50) catch {
      _ => raise McpxDaemonError::Unavailable
    }
  }
  raise McpxDaemonError::Unavailable
}

///|
async fn start_daemon_process() -> Unit raise McpxDaemonError {
  let exe = @sys.get_cli_args().get(0).unwrap_or("mcpx")
  ignore(
    @process.spawn_orphan(exe, [], extra_env={ "MCPX_INTERNAL_DAEMON": "serve" }) catch {
      error => raise McpxDaemonError::ConnectFailed(error.to_string())
    },
  )
}

///|
pub async fn daemon_call_tool(
  home~ : String,
  config_home? : String? = None,
  key~ : String,
  server~ : @config.McpServerConfig,
  tool_name~ : String,
  arguments~ : Json,
) -> Json raise McpxDaemonError {
  ignore(ensure_mcpx_daemon_running(home~, config_home~))
  let req = Json::object({
    "op": Json::string("call_tool"),
    "key": Json::string(key),
    "server": server.to_json(),
    "tool": Json::string(tool_name),
    "args": arguments,
  })
  let response = request(home~, config_home~, req)
  decode_result(response)
}

///|
pub async fn daemon_list_tools(
  home~ : String,
  config_home? : String? = None,
  key~ : String,
  server~ : @config.McpServerConfig,
) -> Array[@mcp_client.McpToolInfo] raise McpxDaemonError {
  ignore(ensure_mcpx_daemon_running(home~, config_home~))
  let req = Json::object({
    "op": Json::string("list_tools"),
    "key": Json::string(key),
    "server": server.to_json(),
  })
  let response = request(home~, config_home~, req)
  decode_tools(response)
}

///|
pub async fn daemon_stop(
  home~ : String,
  config_home? : String? = None,
) -> Bool raise McpxDaemonError {
  let req = Json::object({ "op": Json::string("stop") })
  let response = request(home~, config_home~, req)
  match response {
    Object(obj) => obj.get("ok") == Some(Json::boolean(true))
    _ => false
  }
}

///|
async fn handle_conn(
  conn : @socket.Tcp,
  group : @async.TaskGroup[Unit],
  pool : DaemonPool,
  server : @socket.TcpServer,
) -> Unit {
  let line = conn.read_until("\n") catch { _ => None }
  let response = match line {
    None => error_response("empty request")
    Some(text) => handle_request(text, group, pool, server)
  }
  conn.write(response.stringify() + "\n") catch {
    _ => ()
  }
  conn.close()
}

///|
async fn handle_request(
  text : String,
  group : @async.TaskGroup[Unit],
  pool : DaemonPool,
  server : @socket.TcpServer,
) -> Json {
  let req = @json.parse(text) catch {
    err => return error_response(err.to_string())
  }
  let obj = match req {
    Object(value) => value
    _ => return error_response("request must be object")
  }
  let op = match obj.get("op") {
    Some(String(value)) => value
    _ => ""
  }
  match op {
    "ping" => ok_response(Json::object({}))
    "stop" => {
      server.close()
      ok_response(Json::object({}))
    }
    "call_tool" => handle_call_tool(obj, group, pool)
    "list_tools" => handle_list_tools(obj, group, pool)
    _ => error_response("unknown op")
  }
}

///|
async fn handle_call_tool(
  obj : Map[String, Json],
  group : @async.TaskGroup[Unit],
  pool : DaemonPool,
) -> Json {
  let key = string_field(obj, "key").unwrap_or("")
  let tool_name = string_field(obj, "tool").unwrap_or("")
  let arguments = obj.get("args").unwrap_or(Json::object({}))
  let server = match decode_request_server(obj) {
    Ok(value) => value
    Err(message) => return error_response(message)
  }
  let result : Result[Json, _] = try? ({
    let entry = pool.entry(group, key, server)
    entry.val.mutex.acquire()
    entry.val.mark_used()
    defer {
      entry.val.mark_used()
      entry.val.mutex.release()
    }
    entry.val.client.call_tool(tool_name~, arguments~)
  })
  match result {
    Ok(value) => ok_response(value)
    Err(error) => error_response(error.to_string())
  }
}

///|
async fn handle_list_tools(
  obj : Map[String, Json],
  group : @async.TaskGroup[Unit],
  pool : DaemonPool,
) -> Json {
  let key = string_field(obj, "key").unwrap_or("")
  let server = match decode_request_server(obj) {
    Ok(value) => value
    Err(message) => return error_response(message)
  }
  let result : Result[Array[@mcp_client.McpToolInfo], _] = try? ({
    let entry = pool.entry(group, key, server)
    entry.val.mutex.acquire()
    entry.val.mark_used()
    defer {
      entry.val.mark_used()
      entry.val.mutex.release()
    }
    entry.val.client.list_tools()
  })
  match result {
    Ok(tools) =>
      ok_response(
        Json::object({ "tools": Json::array(tools.map(tool_info_json)) }),
      )
    Err(error) => error_response(error.to_string())
  }
}

///|
async fn DaemonPool::entry(
  self : DaemonPool,
  group : @async.TaskGroup[Unit],
  key : String,
  server : @config.McpServerConfig,
) -> Ref[DaemonEntry] raise McpxDaemonError {
  self.lock.acquire() catch {
    _ => raise McpxDaemonError::Unavailable
  }
  let existing = self.entries.get(key)
  match existing {
    Some(value) if !value.val.is_idle_expired() => {
      self.lock.release()
      value
    }
    Some(value) => {
      self.entries.remove(key)
      self.lock.release()
      close_entry(value)
      create_and_insert_entry(self, group, key, server)
    }
    None => {
      self.lock.release()
      create_and_insert_entry(self, group, key, server)
    }
  }
}

///|
async fn create_and_insert_entry(
  pool : DaemonPool,
  group : @async.TaskGroup[Unit],
  key : String,
  server : @config.McpServerConfig,
) -> Ref[DaemonEntry] raise McpxDaemonError {
  let created = create_entry(group, server)
  pool.lock.acquire() catch {
    _ => raise McpxDaemonError::Unavailable
  }
  match pool.entries.get(key) {
    Some(value) => {
      pool.lock.release()
      created.client.close()
      value
    }
    None => {
      let entry = Ref(created)
      pool.entries[key] = entry
      pool.lock.release()
      entry
    }
  }
}

///|
async fn create_entry(
  group : @async.TaskGroup[Unit],
  server : @config.McpServerConfig,
) -> DaemonEntry raise McpxDaemonError {
  let command = match server.command {
    Some(value) => value
    None => raise McpxDaemonError::RemoteError("server has no command")
  }
  let client = @mcp_stdio.stdio_mcp_connect(
    group,
    command~,
    args=server.args,
    env=server.env,
    cwd=server.cwd,
  ) catch {
    _ => raise McpxDaemonError::Stdio("mcp stdio error")
  }
  {
    client,
    mutex: @async.Semaphore(1),
    idle_timeout_ms: server_idle_timeout_ms(server),
    last_used_ms: @async.now(),
  }
}

///|
fn server_idle_timeout_ms(server : @config.McpServerConfig) -> Int? {
  match server.lifecycle {
    Some({ mode: @config.ServerLifecycleMode::KeepAlive, idle_timeout_ms }) =>
      idle_timeout_ms
    _ => None
  }
}

///|
fn DaemonEntry::is_idle_expired(self : DaemonEntry) -> Bool {
  match self.idle_timeout_ms {
    Some(timeout) => @async.now() - self.last_used_ms >= timeout.to_int64()
    None => false
  }
}

///|
fn DaemonEntry::mark_used(self : DaemonEntry) -> Unit {
  self.last_used_ms = @async.now()
}

///|
fn close_entry(entry : Ref[DaemonEntry]) -> Unit {
  entry.val.client.close()
}

///|
async fn request(
  home~ : String,
  config_home? : String? = None,
  req : Json,
) -> Json raise McpxDaemonError {
  let port = match read_mcpx_daemon_port(home~, config_home~) {
    Some(value) => value
    None => raise McpxDaemonError::Unavailable
  }
  let addr = @socket.Addr::parse("127.0.0.1:\{port}") catch {
    error => raise McpxDaemonError::ConnectFailed(error.to_string())
  }
  let conn = @socket.Tcp::connect(addr) catch {
    error => raise McpxDaemonError::ConnectFailed(error.to_string())
  }
  conn.write(req.stringify() + "\n") catch {
    error => raise McpxDaemonError::ConnectFailed(error.to_string())
  }
  let line = conn.read_until("\n") catch {
    error => raise McpxDaemonError::ConnectFailed(error.to_string())
  }
  conn.close()
  match line {
    None => raise McpxDaemonError::InvalidResponse("empty response")
    Some(text) =>
      @json.parse(text) catch {
        error => raise McpxDaemonError::InvalidResponse(error.to_string())
      }
  }
}

///|
fn decode_request_server(
  obj : Map[String, Json],
) -> Result[@config.McpServerConfig, String] {
  let server_json = match obj.get("server") {
    Some(value) => value
    None => return Err("missing server")
  }
  let wrapped = Json::object({
    "mcpServers": Json::object({ "request": server_json }),
  })
  let config = @config.decode_mcpx_config(wrapped) catch {
    _ => return Err("invalid server")
  }
  match config.servers.get("request") {
    Some(value) => Ok(value)
    None => Err("missing server")
  }
}

///|
fn decode_result(response : Json) -> Json raise McpxDaemonError {
  let obj = expect_response_object(response)
  match obj.get("ok") {
    Some(True) => obj.get("result").unwrap_or(Json::object({}))
    Some(False) => raise McpxDaemonError::RemoteError(error_message(obj))
    _ => raise McpxDaemonError::InvalidResponse("missing ok")
  }
}

///|
fn decode_tools(
  response : Json,
) -> Array[@mcp_client.McpToolInfo] raise McpxDaemonError {
  let result = decode_result(response)
  let wrapped = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "result": result,
  })
  match @mcp_client.decode_mcp_tool_list_response(wrapped, expected_id=1) {
    Ok(value) => value
    Err(_) => raise McpxDaemonError::InvalidResponse("invalid tools")
  }
}

///|
fn tool_info_json(tool : @mcp_client.McpToolInfo) -> Json {
  let obj = Map([])
  obj["name"] = Json::string(tool.name)
  match tool.description {
    Some(value) => obj["description"] = Json::string(value)
    None => ()
  }
  obj["inputSchema"] = tool.input_schema
  Json::object(obj)
}

///|
fn expect_response_object(
  response : Json,
) -> Map[String, Json] raise McpxDaemonError {
  match response {
    Object(obj) => obj
    _ => raise McpxDaemonError::InvalidResponse("response must be object")
  }
}

///|
fn ok_response(result : Json) -> Json {
  Json::object({ "ok": Json::boolean(true), "result": result })
}

///|
fn error_response(message : String) -> Json {
  Json::object({ "ok": Json::boolean(false), "error": Json::string(message) })
}

///|
fn error_message(obj : Map[String, Json]) -> String {
  match obj.get("error") {
    Some(String(value)) => value
    _ => "daemon error"
  }
}

///|
fn string_field(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn write_daemon_state(
  home~ : String,
  config_home? : String? = None,
  port~ : Int,
) -> Unit raise McpxDaemonError {
  let path = mcpx_daemon_state_path(home~, config_home~)
  let body = Json::object({
    "port": Json::number(Double::from_int(port), repr=port.to_string()),
  }).stringify()
  @storage.secure_write_private_atomic(path, body) catch {
    _ => raise McpxDaemonError::Unavailable
  }
}

///|
fn remove_daemon_state(home~ : String, config_home? : String? = None) -> Unit {
  @fs.remove_file(mcpx_daemon_state_path(home~, config_home~)) catch {
    _ => ()
  }
}
