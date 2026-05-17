///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx daemon: reuses keep-alive stdio client" {
  let home = "/tmp/mcpx-daemon-reuse-test/home"
  @fs.remove_file(mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => run_mcpx_daemon_foreground(home~))
    let port = wait_for_daemon_port(home)
    inspect(port > 0, content="true")
    let server = @config.mcp_server_config(
      name="local",
      transport=@config.ServerTransport::Stdio,
      command=Some("/bin/sh"),
      args=["-c", daemon_reuse_script()],
      lifecycle=Some(
        @config.server_lifecycle(@config.ServerLifecycleMode::KeepAlive),
      ),
    )
    let first = daemon_call_tool(
      home~,
      key="local",
      server~,
      tool_name="count",
      arguments=Json::object({}),
    )
    let second = daemon_call_tool(
      home~,
      key="local",
      server~,
      tool_name="count",
      arguments=Json::object({}),
    )
    inspect(
      first.stringify() + "|" + second.stringify(),
      content="{\"call\":1}|{\"call\":2}",
    )
    ignore(daemon_stop(home~))
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx daemon: idle timeout evicts stale stdio client" {
  let home = "/tmp/mcpx-daemon-idle-test/home"
  @fs.remove_file(mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => run_mcpx_daemon_foreground(home~))
    let port = wait_for_daemon_port(home)
    inspect(port > 0, content="true")
    let server = @config.mcp_server_config(
      name="local",
      transport=@config.ServerTransport::Stdio,
      command=Some("/bin/sh"),
      args=["-c", daemon_reuse_script()],
      lifecycle=Some(
        @config.server_lifecycle(
          @config.ServerLifecycleMode::KeepAlive,
          idle_timeout_ms=Some(50),
        ),
      ),
    )
    let first = daemon_call_tool(
      home~,
      key="local",
      server~,
      tool_name="count",
      arguments=Json::object({}),
    )
    @async.sleep(90)
    let second = daemon_call_tool(
      home~,
      key="local",
      server~,
      tool_name="count",
      arguments=Json::object({}),
    )
    inspect(
      first.stringify() + "|" + second.stringify(),
      content="{\"call\":1}|{\"call\":1}",
    )
    ignore(daemon_stop(home~))
  })
}

///|
async fn wait_for_daemon_port(home : String) -> Int {
  for i in 0..<100 {
    ignore(i)
    match read_mcpx_daemon_port(home~) {
      Some(port) => break port
      None => @async.sleep(20)
    }
  } nobreak {
    0
  }
}

///|
fn daemon_reuse_script() -> String {
  (
    #|i=0
    #|while IFS= read -r line; do
    #|  i=$((i + 1))
    #|  if [ "$i" = "1" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{},"serverInfo":{"name":"srv"}}}'
    #|  elif [ "$i" = "3" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"call":1}}'
    #|  elif [ "$i" = "4" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"call":2}}'
    #|  fi
    #|done
  )
}
