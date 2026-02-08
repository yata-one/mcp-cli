///|
/// Daemon process: maintains pooled MCP connections and serves IPC over TCP.

///|
pub using @aio {trait Reader, trait Writer}

///|
pub async fn run_daemon(settings : Settings) -> Unit {
  let p = pool()
  let state = state_path()
  @async.with_task_group(fn(group) {
    let server = @socket.TcpServer::new(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr().port()
    write_port(state, port) catch {
      // If we can't write the state file, the daemon can't be discovered.
      err => {
        println(err.to_string())
        @sys.exit(1)
        panic()
      }
    }
    let last_activity = Ref::new(@async.now())
    let active = Ref::new(0)
    group.spawn_bg(no_wait=true, fn() {
      idle_monitor(last_activity, active, settings.daemon_timeout_ms)
    })
    server.run_forever(max_connections=settings.concurrency, fn(conn, _) {
      handle_conn(conn, group, p, settings, last_activity, active)
    })
  })
}

///|
async fn idle_monitor(
  last_activity : Ref[Int64],
  active : Ref[Int],
  timeout_ms : Int,
) -> Unit {
  for {
    @async.sleep(1000)
    if active.val == 0 &&
      @async.now() - last_activity.val > timeout_ms.to_int64() {
      @sys.exit(0)
    }
  }
}

///|
async fn handle_conn(
  conn : @socket.Tcp,
  group : @async.TaskGroup[Unit],
  p : Pool,
  settings : Settings,
  last_activity : Ref[Int64],
  active : Ref[Int],
) -> Unit {
  active.val = active.val + 1
  defer {
    active.val = active.val - 1
  }
  last_activity.val = @async.now()
  let line = conn.read_until("\n") catch { _ => None }
  match line {
    None => ()
    Some(text) => {
      let resp = handle_request(text, group, p, settings)
      conn.write(resp.stringify() + "\n") catch {
        _ => ()
      }
    }
  }
}

///|
async fn handle_request(
  text : String,
  group : @async.TaskGroup[Unit],
  p : Pool,
  settings : Settings,
) -> Json {
  let req = @json.parse(text) catch {
    err =>
      return Json::object({
        "ok": Json::boolean(false),
        "error": Json::string(err.to_string()),
      })
  }
  let obj = match req {
    Object(o) => o
    _ =>
      return Json::object({
        "ok": Json::boolean(false),
        "error": Json::string("request must be an object"),
      })
  }
  let op = match obj.get("op") {
    Some(String(s)) => s
    _ => ""
  }
  match op {
    "ping" => Json::object({ "ok": Json::boolean(true) })
    "list_tools" => {
      let key = match obj.get("key") {
        Some(String(s)) => s
        _ => ""
      }
      let server_json = obj.get("server").unwrap_or(Json::object({}))
      let server = decode_server_config("server", server_json) catch {
        err =>
          return Json::object({
            "ok": Json::boolean(false),
            "error": Json::string(err.to_string()),
          })
      }
      let result : Result[(Array[ToolInfo], String?), _] = try? p.list_tools(
        group, settings, key, server,
      )
      match result {
        Ok((tools, instructions)) => {
          let tools_json = tools.map(tool_info_to_json)
          let res = Map::new()
          res["tools"] = Json::array(tools_json)
          match instructions {
            None => ()
            Some(t) => res["instructions"] = Json::string(t)
          }
          Json::object({
            "ok": Json::boolean(true),
            "result": Json::object(res),
          })
        }
        Err(err) =>
          Json::object({
            "ok": Json::boolean(false),
            "error": Json::string(err.to_string()),
          })
      }
    }
    "call_tool" => {
      let key = match obj.get("key") {
        Some(String(s)) => s
        _ => ""
      }
      let tool_name = match obj.get("tool") {
        Some(String(s)) => s
        _ => ""
      }
      let args_json = obj.get("args").unwrap_or(Json::object({}))
      let server_json = obj.get("server").unwrap_or(Json::object({}))
      let server = decode_server_config("server", server_json) catch {
        err =>
          return Json::object({
            "ok": Json::boolean(false),
            "error": Json::string(err.to_string()),
          })
      }
      let result : Result[Json, _] = try? p.call_tool(
        group, settings, key, server, tool_name, args_json,
      )
      match result {
        Ok(v) => Json::object({ "ok": Json::boolean(true), "result": v })
        Err(err) =>
          Json::object({
            "ok": Json::boolean(false),
            "error": Json::string(err.to_string()),
          })
      }
    }
    _ =>
      Json::object({
        "ok": Json::boolean(false),
        "error": Json::string("unknown op"),
      })
  }
}
