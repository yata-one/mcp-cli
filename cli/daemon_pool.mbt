///|
/// Connection pooling for MCP servers (daemon-side).

///|
priv enum PooledClient {
  Http(Client[HttpTransport])
  Stdio(Client[StdioTransport])
}

///|
async fn PooledClient::close(self : PooledClient) -> Unit {
  match self {
    Http(c) => c.close() catch { _ => () }
    Stdio(c) => c.close() catch { _ => () }
  }
}

///|
async fn PooledClient::list_tools_with_meta(
  self : PooledClient,
) -> (PooledClient, Array[ToolInfo], String?) {
  match self {
    Http(c) => {
      let tools = c.list_tools()
      let instructions = c.get_instructions()
      (PooledClient::Http(c), tools, instructions)
    }
    Stdio(c) => {
      let tools = c.list_tools()
      let instructions = c.get_instructions()
      (PooledClient::Stdio(c), tools, instructions)
    }
  }
}

///|
async fn PooledClient::call_tool(
  self : PooledClient,
  tool_name : String,
  args_json : Json,
) -> (PooledClient, Json) {
  match self {
    Http(c) => {
      let result = c.call_tool(tool_name, args_json)
      (PooledClient::Http(c), result)
    }
    Stdio(c) => {
      let result = c.call_tool(tool_name, args_json)
      (PooledClient::Stdio(c), result)
    }
  }
}

///|
priv struct Entry {
  mut client : PooledClient
  mutex : @async.Semaphore
}

///|
pub struct Pool {
  priv entries : Map[String, Ref[Entry]]
  priv lock : @async.Semaphore
}

///|
pub fn pool() -> Pool {
  { entries: Map::new(), lock: @async.Semaphore::new(1) }
}

///|
pub async fn Pool::list_tools(
  self : Pool,
  group : @async.TaskGroup[Unit],
  settings : Settings,
  key : String,
  server : ServerConfig,
) -> (Array[ToolInfo], String?) {
  self.with_entry(group, settings, key, server, entry => {
    entry_list_tools(entry, settings)
  })
}

///|
pub async fn Pool::call_tool(
  self : Pool,
  group : @async.TaskGroup[Unit],
  settings : Settings,
  key : String,
  server : ServerConfig,
  tool_name : String,
  args_json : Json,
) -> Json {
  self.with_entry(group, settings, key, server, entry => {
    entry_call_tool(entry, settings, tool_name, args_json)
  })
}

///|
async fn[T] Pool::with_entry(
  self : Pool,
  group : @async.TaskGroup[Unit],
  settings : Settings,
  key : String,
  server : ServerConfig,
  op : async (Ref[Entry]) -> T,
) -> T {
  let entry = self.get_or_create_entry(group, settings, key, server)
  let result : Result[T, _] = try? ({
    entry.val.mutex.acquire()
    defer entry.val.mutex.release()
    op(entry)
  })
  match result {
    Ok(v) => v
    Err(err) => {
      self.remove_entry(key)
      raise err
    }
  }
}

///|
async fn Pool::get_or_create_entry(
  self : Pool,
  group : @async.TaskGroup[Unit],
  settings : Settings,
  key : String,
  server : ServerConfig,
) -> Ref[Entry] {
  self.lock.acquire()
  let existing = self.entries.get(key)
  self.lock.release()
  match existing {
    Some(e) => e
    None => {
      let created = create_entry(group, settings, server)
      self.lock.acquire()
      match self.entries.get(key) {
        Some(e) => {
          self.lock.release()
          created.client.close()
          e
        }
        None => {
          let entry_ref = Ref::new(created)
          self.entries[key] = entry_ref
          self.lock.release()
          entry_ref
        }
      }
    }
  }
}

///|
async fn Pool::remove_entry(self : Pool, key : String) -> Unit {
  self.lock.acquire()
  let entry = self.entries.get(key)
  match entry {
    None => self.lock.release()
    Some(e) => {
      self.entries.remove(key)
      self.lock.release()
      e.val.mutex.acquire()
      let client = e.val.client
      e.val.mutex.release()
      client.close()
    }
  }
}

///|
async fn create_entry(
  group : @async.TaskGroup[Unit],
  settings : Settings,
  server : ServerConfig,
) -> Entry {
  @async.retry(
    @async.RetryMethod::FixedDelay(settings.retry_delay_ms),
    () => {
      @async.with_timeout(settings.timeout_ms, () => {
        match server.transport {
          Transport::Http(url, headers) => {
            let transport = http_transport(url, headers)
            let client = client(transport)
            client.initialize(client_version="0.1.0")
            {
              client: PooledClient::Http(client),
              mutex: @async.Semaphore::new(1),
            }
          }
          Transport::Stdio(command, args, env, cwd) => {
            let transport = connect_stdio(group, command, args, env, cwd)
            let client = client(transport)
            client.initialize(client_version="0.1.0")
            {
              client: PooledClient::Stdio(client),
              mutex: @async.Semaphore::new(1),
            }
          }
        }
      })
    },
    max_retry=settings.max_retries,
  )
}

///|
async fn entry_list_tools(
  entry : Ref[Entry],
  settings : Settings,
) -> (Array[ToolInfo], String?) {
  @async.retry(
    @async.RetryMethod::FixedDelay(settings.retry_delay_ms),
    () => {
      @async.with_timeout(settings.timeout_ms, () => {
        let client = entry.val.client
        let (next_client, tools, instructions) = client.list_tools_with_meta()
        entry.val.client = next_client
        (tools, instructions)
      })
    },
    max_retry=settings.max_retries,
    fatal_error=is_fatal_retry_error,
  )
}

///|
async fn entry_call_tool(
  entry : Ref[Entry],
  settings : Settings,
  tool_name : String,
  args_json : Json,
) -> Json {
  @async.retry(
    @async.RetryMethod::FixedDelay(settings.retry_delay_ms),
    () => {
      @async.with_timeout(settings.timeout_ms, () => {
        let client = entry.val.client
        let (next_client, result) = client.call_tool(tool_name, args_json)
        entry.val.client = next_client
        result
      })
    },
    max_retry=settings.max_retries,
    fatal_error=is_fatal_retry_error,
  )
}
