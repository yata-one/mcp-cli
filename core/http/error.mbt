///|
pub suberror McpHttpClientError {
  HttpStatus(Int)
  Protocol(String)
} derive(Debug)

///|
pub fn mcp_http_client_status_code(error : McpHttpClientError) -> Int? {
  match error {
    HttpStatus(code) => Some(code)
    _ => None
  }
}
