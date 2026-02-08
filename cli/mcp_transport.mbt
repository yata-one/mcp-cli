///|
pub suberror TransportError {
  Closed
  SpawnFailed(String)
  ReadFailed(String)
  WriteFailed(String)
  InvalidJson(String)
}

///|
pub impl Show for TransportError with output(self, logger) {
  match self {
    Closed => logger.write_string("Closed")
    SpawnFailed(msg) => {
      logger.write_string("SpawnFailed(\"")
      logger.write_string(msg)
      logger.write_string("\")")
    }
    ReadFailed(msg) => {
      logger.write_string("ReadFailed(\"")
      logger.write_string(msg)
      logger.write_string("\")")
    }
    WriteFailed(msg) => {
      logger.write_string("WriteFailed(\"")
      logger.write_string(msg)
      logger.write_string("\")")
    }
    InvalidJson(msg) => {
      logger.write_string("InvalidJson(\"")
      logger.write_string(msg)
      logger.write_string("\")")
    }
  }
}

///|
pub(open) trait McpTransport {
  async send(Self, Json) -> Unit raise TransportError
  async recv(Self) -> Json? raise TransportError
  async close(Self) -> Unit raise TransportError
}

///|
/// Test helper transport: deterministic recv queue + captures sent messages.
pub struct MockTransport {
  sent : Array[Json]
  recv_rev : Array[Json]
  mut closed : Bool
} derive(Show)

///|
pub fn mock_transport(recv : Array[Json]) -> MockTransport {
  { sent: [], recv_rev: recv.rev(), closed: false }
}

///|
pub fn MockTransport::sent_messages(self : MockTransport) -> Array[Json] {
  self.sent
}

///|
pub impl McpTransport for MockTransport with send(self, msg) {
  if self.closed {
    raise TransportError::Closed
  }
  self.sent.push(msg)
}

///|
pub impl McpTransport for MockTransport with recv(self) {
  if self.closed {
    return None
  }
  self.recv_rev.pop()
}

///|
pub impl McpTransport for MockTransport with close(self) {
  self.closed = true
}

///|
pub struct StdioTransport {
  reader : @process.ReadFromProcess
  stdout_handle : &@process.ProcessOutput
  writer : @process.WriteToProcess
  stdin_handle : &@process.ProcessInput
  process : @process.Process
  mut closed : Bool
}

///|
pub async fn[X] connect_stdio(
  group : @async.TaskGroup[X],
  command : String,
  args : Array[String],
  env : Map[String, String],
  cwd : String?,
) -> StdioTransport raise TransportError {
  let (reader, stdout_handle) = @process.read_from_process() catch {
    err => raise TransportError::SpawnFailed(err.to_string())
  }
  let (stdin_handle, writer) = @process.write_to_process() catch {
    err => raise TransportError::SpawnFailed(err.to_string())
  }
  let proc = match cwd {
    None =>
      @process.spawn(
        group,
        command,
        args,
        extra_env=env,
        inherit_env=true,
        stdin=stdin_handle,
        stdout=stdout_handle,
        stderr=@stdio.stderr,
      ) catch {
        err => raise TransportError::SpawnFailed(err.to_string())
      }
    Some(dir) =>
      @process.spawn(
        group,
        command,
        args,
        extra_env=env,
        inherit_env=true,
        stdin=stdin_handle,
        stdout=stdout_handle,
        stderr=@stdio.stderr,
        cwd=dir.to_string_view(),
      ) catch {
        err => raise TransportError::SpawnFailed(err.to_string())
      }
  }
  { reader, stdout_handle, writer, stdin_handle, process: proc, closed: false }
}

///|
pub impl McpTransport for StdioTransport with send(self, msg) {
  if self.closed {
    raise TransportError::Closed
  }
  let line = msg.stringify() + "\n"
  self.writer.write(line) catch {
    err => raise TransportError::WriteFailed(err.to_string())
  }
}

///|
pub impl McpTransport for StdioTransport with recv(self) {
  if self.closed {
    return None
  }
  let line = self.reader.read_until("\n") catch {
    err => raise TransportError::ReadFailed(err.to_string())
  }
  match line {
    None => None
    Some(s) =>
      Some(
        @json.parse(s) catch {
          err => raise TransportError::InvalidJson(err.to_string())
        },
      )
  }
}

///|
pub impl McpTransport for StdioTransport with close(self) {
  if self.closed {
    return ()
  }
  self.closed = true
  self.writer.close()
  self.reader.close()
  // Best-effort cancellation; ignore errors.
  self.process.cancel()
}
