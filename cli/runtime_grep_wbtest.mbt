///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: grep searches filtered tools and reuses cache" {
  let home = "/tmp/mcpx-runtime-grep-cache-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @fs.remove_file(paths.cache_file) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="github",
          transport=@config.ServerTransport::Http,
          url=Some("http://localhost:\{port}/mcp"),
          allowed_tools=["search_*", "delete_*"],
          disabled_tools=["delete_*"],
        ),
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
                    "name": Json::string("search_issues"),
                    "description": Json::string("Search issues"),
                    "inputSchema": Json::object({
                      "type": Json::string("object"),
                    }),
                  }),
                  Json::object({
                    "name": Json::string("delete_issue"),
                    "description": Json::string("Delete issue"),
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
    let result = run_mcpx_args_async(["grep", "issue"], home~)
    inspect(
      result,
      content=(
        #|Matches for "issue"
        #|  github/search_issues()
        #|    Search issues
      ),
    )
    inspect(@fs.path_exists(paths.cache_file), content="true")
  })
  let cached = run_mcpx_args_async(["grep", "issue"], home~)
  inspect(
    cached,
    content=(
      #|Matches for "issue"
      #|  github/search_issues()
      #|    Search issues
    ),
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: grep cache key is secret-free" {
  let home = "/tmp/mcpx-runtime-grep-secret-free-cache-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @fs.remove_file(paths.cache_file) catch {
    _ => ()
  }
  @fs.remove_file(paths.env_file) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="github",
          transport=@config.ServerTransport::Http,
          url=Some("http://localhost:\{port}/mcp"),
          headers={ "Authorization": "Bearer ${TOKEN}" },
          auth=Some(
            @config.oauth_server_auth(
              client_id=Some("public-client"),
              client_secret=Some("client-secret"),
              metadata_url=Some("https://auth.example/.well-known/oauth"),
            ),
          ),
        ),
      ),
    )
    @fs.write_string_to_file(paths.env_file, "TOKEN=file-token\n")
    @fs.write_string_to_file(
      paths.cache_file,
      Json::object({
        "version": Json::number(1.0, repr="1"),
        "entries": Json::object({
          "legacy-key-with-legacy-token": Json::object({
            "updatedAtMs": Json::number(0.0, repr="0"),
            "server": Json::string("legacy"),
            "tools": Json::array([]),
          }),
        }),
      }).stringify(),
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
                    "name": Json::string("search_public"),
                    "description": Json::string("Search public data"),
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
    ignore(run_mcpx_args_async(["grep", "search"], home~))
    let cache = @fs.read_file_to_string(paths.cache_file)
    inspect(cache.contains("file-token"), content="false")
    inspect(cache.contains("legacy-token"), content="false")
    inspect(cache.contains("client-secret"), content="false")
    inspect(cache.contains("Bearer file-token"), content="false")
    inspect(cache.contains("Authorization"), content="true")
  })
}

///|
test "mcpx runtime: daemon key is secret-free" {
  let server = @config.mcp_server_config(
    name="github",
    transport=@config.ServerTransport::Http,
    url=Some(
      "https://user-secret@mcp.github.com/mcp?access_token=url-secret#frag",
    ),
    headers={ "Authorization": "Bearer file-token" },
    env={ "TOKEN": "file-token" },
    auth=Some(
      @config.oauth_server_auth(
        client_id=Some("public-client"),
        client_secret=Some("client-secret"),
        metadata_url=Some("https://auth.example/.well-known/oauth"),
      ),
    ),
  )
  let key = daemon_pool_key_for_test("github", server)
  inspect(key.contains("file-token"), content="false")
  inspect(key.contains("client-secret"), content="false")
  inspect(key.contains("Bearer file-token"), content="false")
  inspect(key.contains("user-secret"), content="false")
  inspect(key.contains("url-secret"), content="false")
  inspect(key.contains("https://mcp.github.com/mcp"), content="true")
  inspect(key.contains("Authorization"), content="true")
  inspect(key.contains("TOKEN"), content="true")
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: grep shows matches and skipped HTTP errors" {
  let home = "/tmp/mcpx-runtime-grep-skipped-http-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @fs.remove_file(paths.cache_file) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let ok_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let broken_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer ok_server.close()
    defer broken_server.close()
    let ok_port = ok_server.addr.port()
    let broken_port = broken_server.addr.port()
    let config = @config.put_server_config(
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="github",
          transport=@config.ServerTransport::Http,
          url=Some("http://localhost:\{ok_port}/mcp"),
        ),
      ),
      @config.mcp_server_config(
        name="broken",
        transport=@config.ServerTransport::Http,
        url=Some("http://localhost:\{broken_port}/mcp"),
      ),
    )
    @storage.save_mcpx_config_file(paths.servers_config, config)
    group.spawn_bg(no_wait=true, () => {
      ok_server.run_forever(allow_failure=true, (_request, body, conn) => {
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
                    "name": Json::string("search_issues"),
                    "description": Json::string("Search issues"),
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
    group.spawn_bg(no_wait=true, () => {
      broken_server.run_forever(allow_failure=true, (_request, body, conn) => {
        ignore(body.read_all())
        conn.send_response(500, "Broken")
        conn.end_response()
      })
    })
    let result = run_mcpx_args_async(["grep", "search"], home~)
    inspect(result.contains("Matches for \"search\""), content="true")
    inspect(result.contains("github/search_issues()"), content="true")
    inspect(result.contains("Skipped:"), content="true")
    inspect(result.contains("broken: returned HTTP 500"), content="true")
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: grep shows skipped reasons when no server can be listed" {
  let home = "/tmp/mcpx-runtime-grep-skipped-all-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @fs.remove_file(paths.cache_file) catch {
    _ => ()
  }
  @fs.remove_file(paths.env_file) catch {
    _ => ()
  }
  let config = @config.put_server_config(
    @config.put_server_config(
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="private",
          transport=@config.ServerTransport::Http,
          url=Some("https://private.example/mcp"),
          auth=Some(@config.oauth_server_auth()),
        ),
      ),
      @config.mcp_server_config(
        name="env-missing",
        transport=@config.ServerTransport::Http,
        url=Some("https://env.example/mcp"),
        headers={ "Authorization": "Bearer ${TOKEN}" },
      ),
    ),
    @config.mcp_server_config(
      name="local-broken",
      transport=@config.ServerTransport::Stdio,
      command=Some("/bin/does-not-exist-mcpx"),
    ),
  )
  @storage.save_mcpx_config_file(paths.servers_config, config)
  let result = run_mcpx_args_async(["grep", "search"], home~)
  inspect(result.contains("No tools matched \"search\""), content="true")
  inspect(result.contains("Skipped:"), content="true")
  inspect(
    result.contains("private: authentication required: run mcpx auth private"),
    content="true",
  )
  inspect(
    result.contains("env-missing: MissingEnvVar(\"TOKEN\")"),
    content="true",
  )
  inspect(result.contains("local-broken: mcp stdio error"), content="true")
}
