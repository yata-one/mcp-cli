///|
#cfg(all(target="native", not(platform="windows")))
async test "pool: http connection is reused (initialize once)" {
  let init = []
  let list = []
  let call = []
  @async.with_task_group(group => {
    let mcp_server = @http.Server::new(@socket.Addr::parse("127.0.0.1:0"))
    defer mcp_server.close()
    let port = mcp_server.addr().port()
    group.spawn_bg(no_wait=true, () => {
      mcp_server.run_forever(allow_failure=true, (_request, body, conn) => {
        let text = body.read_all().text()
        let msg = @json.parse(text)
        let rpc_method = match msg {
          Object(o) =>
            match o.get("method") {
              Some(String(m)) => m
              _ => ""
            }
          _ => ""
        }
        if rpc_method == "initialize" {
          init.push(())
          let id = match msg {
            Object(o) => o.get("id").unwrap_or(Json::number(1.0))
            _ => Json::number(1.0)
          }
          let result = Json::object({
            "protocolVersion": Json::string("2025-03-26"),
            "capabilities": Json::object({}),
            "serverInfo": Json::object({ "name": Json::string("srv") }),
            "instructions": Json::string("hi"),
          })
          let resp = Json::object({
            "jsonrpc": Json::string("2.0"),
            "id": id,
            "result": result,
          })
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
            "Mcp-Session-Id": "sid123",
          })
          conn..write(resp.stringify()).end_response()
        } else if rpc_method == "notifications/initialized" {
          conn.send_response(202, "Accepted")
          conn.end_response()
        } else if rpc_method == "tools/list" {
          list.push(())
          let id = match msg {
            Object(o) => o.get("id").unwrap_or(Json::number(2.0))
            _ => Json::number(2.0)
          }
          let resp = Json::object({
            "jsonrpc": Json::string("2.0"),
            "id": id,
            "result": Json::object({ "tools": Json::array([]) }),
          })
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn..write(resp.stringify()).end_response()
        } else if rpc_method == "tools/call" {
          call.push(())
          let id = match msg {
            Object(o) => o.get("id").unwrap_or(Json::number(3.0))
            _ => Json::number(3.0)
          }
          let resp = Json::object({
            "jsonrpc": Json::string("2.0"),
            "id": id,
            "result": Json::object({ "ok": Json::boolean(true) }),
          })
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn..write(resp.stringify()).end_response()
        } else {
          conn.send_response(500, "Unknown")
          conn.end_response()
        }
      })
    })
    let server = decode_server_config(
      "s",
      Json::object({ "url": Json::string("http://localhost:\{port}/mcp") }),
    )
    let settings = settings_from_env({})
    let p = pool()
    let (tools1, instr1) = p.list_tools(group, settings, "k", server)
    inspect(tools1.length(), content="0")
    inspect(instr1, content="Some(\"hi\")")
    let (tools2, instr2) = p.list_tools(group, settings, "k", server)
    inspect(tools2.length(), content="0")
    inspect(instr2, content="Some(\"hi\")")
    let result = p.call_tool(
      group,
      settings,
      "k",
      server,
      "t",
      Json::object({}),
    )
    inspect(result.stringify(), content="{\"ok\":true}")
  })
  inspect(init.length(), content="1")
  inspect(list.length(), content="2")
  inspect(call.length(), content="1")
}
