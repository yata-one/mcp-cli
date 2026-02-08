///|
pub suberror McpError {
  Transport(TransportError)
  Protocol(String)
  RemoteError(Int, String)
  UnexpectedEof
}

///|
pub impl Show for McpError with output(self, logger) {
  match self {
    Transport(err) => {
      logger.write_string("Transport(")
      err.output(logger)
      logger.write_string(")")
    }
    Protocol(msg) => {
      logger.write_string("Protocol(\"")
      logger.write_string(msg)
      logger.write_string("\")")
    }
    RemoteError(code, msg) => {
      logger.write_string("RemoteError(")
      code.output(logger)
      logger.write_string(", \"")
      logger.write_string(msg)
      logger.write_string("\")")
    }
    UnexpectedEof => logger.write_string("UnexpectedEof")
  }
}

///|
pub struct ToolInfo {
  name : String
  description : String?
  input_schema : Json
} derive(Show)

///|
pub struct Client[T] {
  transport : T
  mut next_id : Int
  mut instructions : String?
}

///|
pub fn[T] client(transport : T) -> Client[T] {
  { transport, next_id: 1, instructions: None }
}

///|
pub fn tool_info(
  name : String,
  description? : String,
  input_schema? : Json,
) -> ToolInfo {
  { name, description, input_schema: input_schema.unwrap_or_default() }
}

///|
pub fn tool_info_to_json(tool : ToolInfo) -> Json {
  let obj = Map::new()
  obj["name"] = Json::string(tool.name)
  match tool.description {
    None => ()
    Some(desc) => obj["description"] = Json::string(desc)
  }
  obj["inputSchema"] = tool.input_schema
  Json::object(obj)
}

///|
pub fn tool_info_from_json(json : Json) -> ToolInfo raise McpError {
  decode_tool(json)
}

///|
pub fn[T] Client::get_instructions(self : Client[T]) -> String? {
  self.instructions
}

///|
pub async fn[T : McpTransport] Client::initialize(
  self : Client[T],
  client_name? : String = "mcp-cli",
  client_version? : String = "0.0.0",
  protocol_version? : String = "2025-03-26",
) -> Unit raise McpError {
  let params = Map::new()
  params["protocolVersion"] = Json::string(protocol_version)
  params["capabilities"] = Json::object(Map::new())
  let client_info = Map::new()
  client_info["name"] = Json::string(client_name)
  client_info["version"] = Json::string(client_version)
  params["clientInfo"] = Json::object(client_info)
  let result = self.request("initialize", Some(Json::object(params)))
  self.instructions = decode_instructions(result)
  self.notify("notifications/initialized", None)
}

///|
pub async fn[T : McpTransport] Client::list_tools(
  self : Client[T],
) -> Array[ToolInfo] raise McpError {
  let result = self.request("tools/list", Some(Json::object(Map::new())))
  decode_tool_list_result(result)
}

///|
pub async fn[T : McpTransport] Client::call_tool(
  self : Client[T],
  name : String,
  arguments : Json,
) -> Json raise McpError {
  let params = Map::new()
  params["name"] = Json::string(name)
  params["arguments"] = arguments
  self.request("tools/call", Some(Json::object(params)))
}

///|
pub async fn[T : McpTransport] Client::close(
  self : Client[T],
) -> Unit raise McpError {
  self.transport.close() catch {
    err => raise McpError::Transport(err)
  }
}

///|
async fn[T : McpTransport] Client::notify(
  self : Client[T],
  rpc_method : String,
  params : Json?,
) -> Unit raise McpError {
  let msg = encode_notification(rpc_method, params)
  self.transport.send(msg) catch {
    err => raise McpError::Transport(err)
  }
}

///|
async fn[T : McpTransport] Client::request(
  self : Client[T],
  rpc_method : String,
  params : Json?,
) -> Json raise McpError {
  let id = self.next_id
  self.next_id = self.next_id + 1
  let msg = encode_request(id, rpc_method, params)
  self.transport.send(msg) catch {
    err => raise McpError::Transport(err)
  }
  loop () {
    _ => {
      let next = self.transport.recv() catch {
        err => raise McpError::Transport(err)
      }
      match next {
        None => raise McpError::UnexpectedEof
        Some(json) =>
          match decode_response_for_id(json, id) {
            None => continue ()
            Some(result) => result
          }
      }
    }
  }
}

///|
fn decode_response_for_id(msg : Json, id : Int) -> Json? raise McpError {
  let obj = match msg {
    Object(o) => o
    _ => return None
  }
  // notifications don't have "id"
  let msg_id = match obj.get("id") {
    None => return None
    Some(j) => j
  }
  let msg_id_int = match decode_id(msg_id) {
    Some(n) => n
    None => return None
  }
  if msg_id_int != id {
    return None
  }
  match (obj.get("result"), obj.get("error")) {
    (Some(result), _) => Some(result)
    (_, Some(err)) => raise decode_rpc_error(err)
    _ => raise McpError::Protocol("response missing result/error")
  }
}

///|
fn decode_rpc_error(err : Json) -> McpError {
  match err {
    Object(o) => {
      let code = match o.get("code") {
        Some(Number(d, ..)) => d.to_int()
        _ => -1
      }
      let message = match o.get("message") {
        Some(String(s)) => s
        _ => "unknown error"
      }
      McpError::RemoteError(code, message)
    }
    _ => McpError::RemoteError(-1, "invalid rpc error")
  }
}

///|
fn decode_instructions(result : Json) -> String? {
  match result {
    Object(o) =>
      match o.get("instructions") {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
fn decode_tool_list_result(result : Json) -> Array[ToolInfo] raise McpError {
  match result {
    Object(o) =>
      match o.get("tools") {
        Some(Array(arr)) => arr.map(decode_tool)
        _ => raise McpError::Protocol("tools/list result missing tools[]")
      }
    _ => raise McpError::Protocol("tools/list result must be an object")
  }
}

///|
fn decode_tool(tool : Json) -> ToolInfo raise McpError {
  let obj = match tool {
    Object(o) => o
    _ => raise McpError::Protocol("tool must be an object")
  }
  let name = match obj.get("name") {
    Some(String(s)) => s
    _ => raise McpError::Protocol("tool.name must be a string")
  }
  let description = match obj.get("description") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let input_schema = match obj.get("inputSchema") {
    Some(schema) => schema
    None => Json::object(Map::new())
  }
  { name, description, input_schema }
}
