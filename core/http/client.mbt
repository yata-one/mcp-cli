///|
pub async fn list_tools(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
) -> Array[@protocol.McpToolInfo] raise McpHttpClientError {
  let session_id = Ref(None)
  let client = @protocol.mcp_client(client_name="mcpx", client_version="0.1.0")
  initialize(fetch, endpoint, client, session_id)
  let list = client.tools_list_request()
  let list_response = send_json(fetch, endpoint, session_id, list.message)
  let json = payload_json(list_response)
  client.accept_tools_list_response(list, json) catch {
    _ => raise McpHttpClientError::Protocol("mcp protocol error")
  }
}

///|
pub async fn call_tool(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  tool_name~ : String,
  arguments~ : Json,
) -> Json raise McpHttpClientError {
  let session_id = Ref(None)
  let client = @protocol.mcp_client(client_name="mcpx", client_version="0.1.0")
  initialize(fetch, endpoint, client, session_id)
  let call = client.tool_call_request(name=tool_name, arguments~)
  let call_response = send_json(fetch, endpoint, session_id, call.message)
  let json = payload_json(call_response)
  client.accept_tool_call_response(call, json) catch {
    _ => raise McpHttpClientError::Protocol("mcp protocol error")
  }
}

///|
async fn initialize(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  client : @protocol.McpClient,
  session_id : Ref[String?],
) -> Unit raise McpHttpClientError {
  let init = client.initialize_request()
  let init_response = send_json(fetch, endpoint, session_id, init.message)
  let init_json = payload_json(init_response)
  ignore(
    client.accept_initialize_response(init, init_json) catch {
      _ => raise McpHttpClientError::Protocol("mcp protocol error")
    },
  )
  let initialized = client.initialized_notification()
  ignore(send_json(fetch, endpoint, session_id, initialized.message))
}

///|
async fn send_json(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  session_id : Ref[String?],
  message : Json,
) -> @protocol.McpTransportPayload raise McpHttpClientError {
  let response = fetch({
    http_method: "POST",
    url: endpoint.url,
    headers: build_headers(endpoint.headers, session_id.val),
    body: message.stringify(),
  }) catch {
    err => raise McpHttpClientError::Protocol(err.to_string())
  }
  update_session_id(session_id, response.headers)
  if response.status_code != 200 && response.status_code != 202 {
    raise McpHttpClientError::HttpStatus(response.status_code)
  }
  let payload = @protocol.decode_mcp_transport_payload(
    @protocol.mcp_transport_response(
      status_code=response.status_code,
      content_type=response.content_type,
      body=response.body,
    ),
  )
  match payload {
    Ok(value) => value
    Err(_) => raise McpHttpClientError::Protocol("mcp protocol error")
  }
}

///|
fn payload_json(
  payload : @protocol.McpTransportPayload,
) -> Json raise McpHttpClientError {
  @protocol.expect_json_payload(payload) catch {
    _ => raise McpHttpClientError::Protocol("mcp protocol error")
  }
}

///|
fn build_headers(
  base_headers : Map[String, String],
  session_id : String?,
) -> Map[String, String] {
  let headers = base_headers.copy()
  headers["content-type"] = "application/json"
  headers["accept"] = "application/json, text/event-stream"
  match session_id {
    Some(value) => headers["Mcp-Session-Id"] = value
    None => ()
  }
  headers
}

///|
fn update_session_id(
  session_id : Ref[String?],
  headers : Map[String, String],
) -> Unit {
  match header(headers, "Mcp-Session-Id") {
    Some(value) => session_id.val = Some(value)
    None => ()
  }
}

///|
fn header(headers : Map[String, String], key : String) -> String? {
  match headers.get(key) {
    Some(value) => Some(value)
    None => headers.get(key.to_lower())
  }
}
