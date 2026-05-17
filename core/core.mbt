///|
/// Facade package for mcpx shared library APIs.
pub async fn list_tools(
  fetch : async (@http.HttpRequest) -> @http.HttpResponse,
  endpoint : @http.Endpoint,
) -> Array[@protocol.McpToolInfo] raise @http.McpHttpClientError {
  @http.list_tools(fetch, endpoint)
}

///|
pub async fn call_tool(
  fetch : async (@http.HttpRequest) -> @http.HttpResponse,
  endpoint : @http.Endpoint,
  tool_name~ : String,
  arguments~ : Json,
) -> Json raise @http.McpHttpClientError {
  @http.call_tool(fetch, endpoint, tool_name~, arguments~)
}
