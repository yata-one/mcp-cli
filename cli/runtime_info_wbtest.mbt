///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: info uses configured remote HTTP server" {
  let home = "/tmp/mcpx-runtime-list-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_remote_mcp_server(
        @config.empty_mcpx_config(),
        name="github",
        url="http://localhost:\{port}/mcp",
      ),
    )
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (_request, body, conn) => {
        let msg = @json.parse(body.read_all().text())
        let rpc_method = match msg {
          Object(obj) =>
            match obj.get("method") {
              Some(String(value)) => value
              _ => ""
            }
          _ => ""
        }
        let id = match msg {
          Object(obj) => obj.get("id").unwrap_or(Json::number(1.0, repr="1"))
          _ => Json::number(1.0, repr="1")
        }
        if rpc_method == "initialize" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
            "Mcp-Session-Id": "sid-list",
          })
          conn
          ..write(
            Json::object({
              "jsonrpc": Json::string("2.0"),
              "id": id,
              "result": Json::object({
                "protocolVersion": Json::string("2025-03-26"),
                "capabilities": Json::object({}),
                "serverInfo": Json::object({ "name": Json::string("srv") }),
              }),
            }).stringify(),
          )
          .end_response()
        } else if rpc_method == "notifications/initialized" {
          conn.send_response(202, "Accepted")
          conn.end_response()
        } else if rpc_method == "tools/list" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn
          ..write(
            Json::object({
              "jsonrpc": Json::string("2.0"),
              "id": id,
              "result": Json::object({
                "tools": Json::array([
                  Json::object({
                    "name": Json::string("search"),
                    "description": Json::string("Search things"),
                    "inputSchema": Json::object({
                      "type": Json::string("object"),
                    }),
                  }),
                ]),
              }),
            }).stringify(),
          )
          .end_response()
        } else {
          conn.send_response(500, "Unknown")
          conn.end_response()
        }
      })
    })
    let result = run_mcpx_args_async(["info", "github"], home~)
    inspect(
      result,
      content=(
        #|Tools
        #|  search()
        #|    Search things
      ),
    )
    let schema = run_mcpx_args_async(["info", "github", "search"], home~)
    inspect(
      schema,
      content=(
        #|Tool: github/search
        #|
        #|Search things
        #|
        #|Arguments:
        #|  (none)
      ),
    )
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: info without target lists configured servers" {
  let home = "/tmp/mcpx-runtime-info-servers-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @storage.save_mcpx_config_file(
    paths.servers_config,
    @config.put_remote_mcp_server(
      @config.empty_mcpx_config(),
      name="github",
      url="https://mcp.github.com/mcp",
    ),
  )
  inspect(
    run_mcpx_args_async(["info"], home~),
    content=(
      #|Servers
      #|  github  http  https://mcp.github.com/mcp
    ),
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: info can use direct remote URL without config" {
  let home = "/tmp/mcpx-runtime-list-direct-url-test/home"
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (_request, body, conn) => {
        let msg = @json.parse(body.read_all().text())
        let rpc_method = match msg {
          Object(obj) =>
            match obj.get("method") {
              Some(String(value)) => value
              _ => ""
            }
          _ => ""
        }
        let id = match msg {
          Object(obj) => obj.get("id").unwrap_or(Json::number(1.0, repr="1"))
          _ => Json::number(1.0, repr="1")
        }
        if rpc_method == "initialize" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn
          ..write(
            Json::object({
              "jsonrpc": Json::string("2.0"),
              "id": id,
              "result": Json::object({
                "protocolVersion": Json::string("2025-03-26"),
                "capabilities": Json::object({}),
                "serverInfo": Json::object({ "name": Json::string("srv") }),
              }),
            }).stringify(),
          )
          .end_response()
        } else if rpc_method == "notifications/initialized" {
          conn.send_response(202, "Accepted")
          conn.end_response()
        } else if rpc_method == "tools/list" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn
          ..write(
            Json::object({
              "jsonrpc": Json::string("2.0"),
              "id": id,
              "result": Json::object({
                "tools": Json::array([
                  Json::object({
                    "name": Json::string("search"),
                    "inputSchema": Json::object({
                      "type": Json::string("object"),
                    }),
                  }),
                ]),
              }),
            }).stringify(),
          )
          .end_response()
        } else {
          conn.send_response(500, "Unknown")
          conn.end_response()
        }
      })
    })
    let result = run_mcpx_args_async(
      ["info", "http://localhost:\{port}/mcp"],
      home~,
    )
    inspect(
      result,
      content=(
        #|Tools
        #|  search()
      ),
    )
  })
}
