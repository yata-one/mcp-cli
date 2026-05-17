///|
pub struct McpSession {
  mut initialized : Bool
  mut next_id : Int
  mut protocol_version : String?
  mut server_name : String?
  mut server_version : String?
  mut capabilities : Json?
} derive(Debug)

///|
pub fn mcp_session() -> McpSession {
  {
    initialized: false,
    next_id: 1,
    protocol_version: None,
    server_name: None,
    server_version: None,
    capabilities: None,
  }
}

///|
pub fn McpSession::is_initialized(self : McpSession) -> Bool {
  self.initialized
}

///|
pub fn McpSession::next_request_id(self : McpSession) -> Int {
  let id = self.next_id
  self.next_id = id + 1
  id
}

///|
pub fn McpSession::mark_initialized(
  self : McpSession,
  info : McpInitializeInfo,
) -> Unit {
  self.initialized = true
  self.protocol_version = Some(info.protocol_version)
  self.server_name = info.server_name
  self.server_version = info.server_version
  self.capabilities = Some(info.capabilities)
}
