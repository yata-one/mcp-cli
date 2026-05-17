///|
suberror McpHttpError {
  HttpStatus(Int)
  Protocol(String)
} derive(Debug)

///|
pub fn mcp_http_status_code(error : McpHttpError) -> Int? {
  match error {
    HttpStatus(code) => Some(code)
    _ => None
  }
}

///|
pub fn mcp_http_is_protocol_error(error : McpHttpError) -> Bool {
  match error {
    Protocol(_) => true
    _ => false
  }
}

///|
pub async fn http_mcp_call_tool(
  url~ : String,
  headers~ : Map[String, String],
  tool_name~ : String,
  arguments~ : Json,
) -> Json raise McpHttpError {
  @core_http.call_tool(
    native_fetch,
    @core_http.http_endpoint(url~, headers~),
    tool_name~,
    arguments~,
  ) catch {
    error => raise core_error_to_native(error)
  }
}

///|
pub async fn http_mcp_list_tools(
  url~ : String,
  headers~ : Map[String, String],
) -> Array[@mcp_client.McpToolInfo] raise McpHttpError {
  @core_http.list_tools(native_fetch, @core_http.http_endpoint(url~, headers~)) catch {
    error => raise core_error_to_native(error)
  }
}

///|
async fn native_fetch(
  request : @core_http.HttpRequest,
) -> @core_http.HttpResponse {
  let (response, data) = @async_http.post(
    request.url,
    request.body,
    headers=request.headers,
  ) catch {
    error =>
      return @core_http.http_response(
        status_code=599,
        content_type=Some("text/plain"),
        body=error.to_string(),
      )
  }
  let content_type = header(response.headers, "content-type")
  let body = if response.code == 202 {
    ""
  } else {
    data.text() catch {
      _ => ""
    }
  }
  @core_http.http_response(
    status_code=response.code,
    content_type~,
    headers=response.headers,
    body~,
  )
}

///|
fn core_error_to_native(error : @core_http.McpHttpClientError) -> McpHttpError {
  match error {
    @core_http.McpHttpClientError::HttpStatus(code) =>
      McpHttpError::HttpStatus(code)
    @core_http.McpHttpClientError::Protocol(message) =>
      McpHttpError::Protocol(message)
  }
}

///|
fn header(headers : Map[String, String], key : String) -> String? {
  match headers.get(key) {
    Some(value) => Some(value)
    None => headers.get(key.to_lower())
  }
}
