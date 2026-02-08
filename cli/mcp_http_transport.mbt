///|
/// Streamable HTTP transport (minimal).
///
/// This implementation follows the MCP "Streamable HTTP" transport:
/// - Each outgoing JSON-RPC message is sent as an HTTP POST.
/// - Requests (messages with `id`) get a response body:
///   - `application/json` (single JSON-RPC response) OR
///   - `text/event-stream` (SSE; multiple JSON-RPC messages)
/// - Notifications (no `id`) typically get `202 Accepted` with empty body.
///
/// For now we only handle server->client messages that arrive in the POST response
/// (JSON or SSE). This covers the common request/response path used by this CLI.

///|
pub struct HttpTransport {
  url : String
  base_headers : Map[String, String]
  mut session_id : String?
  recv_rev : Array[Json]
  mut closed : Bool
} derive(Show)

///|
pub fn http_transport(
  url : String,
  headers : Map[String, String],
) -> HttpTransport {
  {
    url,
    base_headers: headers.copy(),
    session_id: None,
    recv_rev: [],
    closed: false,
  }
}

///|
pub impl McpTransport for HttpTransport with send(self, msg) {
  if self.closed {
    raise TransportError::Closed
  }
  let headers = build_headers(self)
  let body = msg.stringify()
  let (resp, data) = @http.post(self.url, body, headers~) catch {
    err => raise TransportError::ReadFailed(err.to_string())
  }
  update_session_id(self, resp.headers)
  if is_request(msg) {
    if resp.code != 200 {
      raise TransportError::ReadFailed("http " + resp.code.to_string())
    }
    let msgs = decode_response_messages(resp.headers, data)
    enqueue(self, msgs)
    // For notifications we accept 200 or 202.
  } else if resp.code != 200 && resp.code != 202 {
    raise TransportError::ReadFailed("http " + resp.code.to_string())
  }
}

///|
pub impl McpTransport for HttpTransport with recv(self) {
  if self.closed {
    return None
  }
  self.recv_rev.pop()
}

///|
pub impl McpTransport for HttpTransport with close(self) {
  self.closed = true
}

///|
fn build_headers(transport : HttpTransport) -> Map[String, String] {
  let headers = transport.base_headers.copy()
  headers["content-type"] = "application/json"
  headers["accept"] = "application/json, text/event-stream"
  match transport.session_id {
    None => ()
    Some(sid) => headers["Mcp-Session-Id"] = sid
  }
  headers
}

///|
fn update_session_id(
  transport : HttpTransport,
  headers : Map[String, String],
) -> Unit {
  match header(headers, "Mcp-Session-Id") {
    None =>
      match header(headers, "MCP-Session-Id") {
        None => ()
        Some(s) => transport.session_id = Some(s)
      }
    Some(s) => transport.session_id = Some(s)
  }
}

///|
fn header(headers : Map[String, String], key : String) -> String? {
  match headers.get(key) {
    Some(v) => Some(v)
    None => headers.get(key.to_lower())
  }
}

///|
fn is_request(msg : Json) -> Bool {
  match msg {
    Object(o) => o.get("id") is Some(_)
    _ => false
  }
}

///|
fn decode_response_messages(
  headers : Map[String, String],
  data : &@aio.Data,
) -> Array[Json] raise TransportError {
  let content_type = header(headers, "content-type").unwrap_or_default()
  let ct = content_type.to_lower()
  if ct.contains("text/event-stream") {
    let text = data.text() catch {
      err => raise TransportError::ReadFailed(err.to_string())
    }
    decode_sse_data(text).map(fn(s) {
      @json.parse(s) catch {
        err => raise TransportError::InvalidJson(err.to_string())
      }
    })
  } else {
    let json = data.json() catch {
      err => raise TransportError::InvalidJson(err.to_string())
    }
    [json]
  }
}

///|
fn enqueue(transport : HttpTransport, msgs : Array[Json]) -> Unit {
  for m in msgs.rev() {
    transport.recv_rev.push(m)
  }
}
