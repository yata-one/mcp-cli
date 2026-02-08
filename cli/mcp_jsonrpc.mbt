///|
/// JSON-RPC helpers (MCP uses JSON-RPC 2.0).
///
/// We keep this layer "Json-in/Json-out" so transports can stay simple.

///|
pub fn json_int(n : Int) -> Json {
  Json::number(Double::from_int(n), repr=n.to_string())
}

///|
pub fn encode_request(id : Int, rpc_method : String, params : Json?) -> Json {
  let obj = Map::new()
  obj["jsonrpc"] = Json::string("2.0")
  obj["id"] = json_int(id)
  obj["method"] = Json::string(rpc_method)
  match params {
    Some(p) => obj["params"] = p
    None => ()
  }
  Json::object(obj)
}

///|
pub fn encode_notification(rpc_method : String, params : Json?) -> Json {
  let obj = Map::new()
  obj["jsonrpc"] = Json::string("2.0")
  obj["method"] = Json::string(rpc_method)
  match params {
    Some(p) => obj["params"] = p
    None => ()
  }
  Json::object(obj)
}

///|
pub fn decode_id(id : Json) -> Int? {
  match id {
    Number(d, ..) => if d.trunc() == d { Some(d.to_int()) } else { None }
    _ => None
  }
}
