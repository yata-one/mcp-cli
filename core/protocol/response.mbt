///|
pub struct McpInitializeInfo {
  protocol_version : String
  server_name : String?
  server_version : String?
  capabilities : Json
} derive(Debug)

///|
pub fn decode_mcp_initialize_response(
  response : Json,
  expected_id~ : Int,
) -> Result[McpInitializeInfo, McpProtocolError] {
  let result = decode_mcp_result(response, expected_id~) catch {
    error => return Err(error)
  }
  match result {
    Object(obj) => {
      let protocol_version = match obj.get("protocolVersion") {
        Some(String(value)) => value
        _ =>
          return Err(
            McpProtocolError::InvalidResponse(
              "initialize result missing protocolVersion",
            ),
          )
      }
      let capabilities = obj.get("capabilities").unwrap_or(Json::object({}))
      let (server_name, server_version) = decode_server_info(
        obj.get("serverInfo"),
      )
      Ok({ protocol_version, server_name, server_version, capabilities })
    }
    _ =>
      Err(McpProtocolError::InvalidResponse("initialize result must be object"))
  }
}

///|
pub fn decode_mcp_tool_list_response(
  response : Json,
  expected_id~ : Int,
) -> Result[Array[McpToolInfo], McpProtocolError] {
  let result = decode_mcp_result(response, expected_id~) catch {
    error => return Err(error)
  }
  match result {
    Object(obj) =>
      match obj.get("tools") {
        Some(Array(tools)) => {
          let decoded = []
          for tool in tools {
            match decode_mcp_tool(tool) {
              Ok(value) => decoded.push(value)
              Err(error) => return Err(error)
            }
          }
          Ok(decoded)
        }
        _ =>
          Err(
            McpProtocolError::InvalidResponse("tools/list result missing tools"),
          )
      }
    _ =>
      Err(McpProtocolError::InvalidResponse("tools/list result must be object"))
  }
}

///|
pub fn decode_mcp_result(
  response : Json,
  expected_id~ : Int,
) -> Json raise McpProtocolError {
  let obj = match response {
    Object(value) => value
    _ => raise McpProtocolError::InvalidResponse("response must be object")
  }
  match decode_response_id(obj.get("id")) {
    Some(id) if id == expected_id => ()
    _ => raise McpProtocolError::InvalidResponse("unexpected response id")
  }
  match (obj.get("result"), obj.get("error")) {
    (Some(result), _) => result
    (_, Some(error)) => raise decode_mcp_error(error)
    _ =>
      raise McpProtocolError::InvalidResponse("response missing result/error")
  }
}

///|
pub fn mcp_response_id(message : Json) -> Int? {
  match message {
    Object(obj) => decode_response_id(obj.get("id"))
    _ => None
  }
}

///|
fn decode_mcp_tool(json : Json) -> Result[McpToolInfo, McpProtocolError] {
  let obj = match json {
    Object(value) => value
    _ => return Err(McpProtocolError::InvalidResponse("tool must be object"))
  }
  let name = match obj.get("name") {
    Some(String(value)) => value
    _ =>
      return Err(McpProtocolError::InvalidResponse("tool.name must be string"))
  }
  let description = match obj.get("description") {
    Some(String(value)) => Some(value)
    _ => None
  }
  let input_schema = obj.get("inputSchema").unwrap_or(Json::object(Map([])))
  Ok({ name, description, input_schema })
}

///|
fn decode_server_info(json : Json?) -> (String?, String?) {
  match json {
    Some(Object(obj)) => {
      let name = match obj.get("name") {
        Some(String(value)) => Some(value)
        _ => None
      }
      let version = match obj.get("version") {
        Some(String(value)) => Some(value)
        _ => None
      }
      (name, version)
    }
    _ => (None, None)
  }
}

///|
fn decode_response_id(json : Json?) -> Int? {
  match json {
    Some(Number(value, ..)) if value.trunc() == value => Some(value.to_int())
    _ => None
  }
}

///|
fn decode_mcp_error(json : Json) -> McpProtocolError {
  match json {
    Object(obj) => {
      let code = match obj.get("code") {
        Some(Number(value, ..)) => value.to_int()
        _ => -1
      }
      let message = match obj.get("message") {
        Some(String(value)) => value
        _ => "unknown error"
      }
      McpProtocolError::RemoteError(code, message)
    }
    _ => McpProtocolError::RemoteError(-1, "invalid error")
  }
}
