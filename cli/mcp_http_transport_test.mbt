///|
#cfg(all(target="native", not(platform="windows")))
async test "http transport: session id + sse response" {
  let log = []
  @async.with_task_group(group => {
    let server = @http.Server::new(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr().port()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (request, body, conn) => {
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
          let id = match msg {
            Object(o) => o.get("id").unwrap_or(Json::number(1.0))
            _ => Json::number(1.0)
          }
          let result = Json::object({
            "protocolVersion": Json::string("2025-03-26"),
            "capabilities": Json::object({}),
            "serverInfo": Json::object({ "name": Json::string("srv") }),
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
          let sid = request.headers.get("mcp-session-id").unwrap_or("none")
          log.push(sid)
          let notify = Json::object({
            "jsonrpc": Json::string("2.0"),
            "method": Json::string("notifications/log"),
            "params": Json::object({}),
          })
          let id = match msg {
            Object(o) => o.get("id").unwrap_or(Json::number(2.0))
            _ => Json::number(2.0)
          }
          let resp = Json::object({
            "jsonrpc": Json::string("2.0"),
            "id": id,
            "result": Json::object({ "tools": Json::array([]) }),
          })
          let sse = "data: " +
            notify.stringify() +
            "\n\n" +
            "data: " +
            resp.stringify() +
            "\n\n"
          conn.send_response(200, "OK", extra_headers={
            "content-type": "text/event-stream",
          })
          conn..write(sse).end_response()
        } else {
          conn.send_response(500, "Unknown")
          conn.end_response()
        }
      })
    })
    let t = http_transport("http://localhost:\{port}/mcp", Map::new())
    let c = client(t)
    c.initialize(client_version="0.1.0")
    let tools = c.list_tools()
    inspect(tools.length(), content="0")
    c.close()
  })
  inspect(log, content="[\"sid123\"]")
}
