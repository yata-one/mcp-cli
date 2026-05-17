///|
pub struct McpTransportResponse {
  status_code : Int
  content_type : String?
  body : String
} derive(Debug)

///|
pub(all) enum McpTransportPayload {
  JsonPayload(Json)
  AcceptedNoContent
} derive(Debug)

///|
pub fn mcp_transport_response(
  status_code~ : Int,
  content_type~ : String?,
  body~ : String,
) -> McpTransportResponse {
  { status_code, content_type, body }
}

///|
pub fn decode_mcp_transport_payload(
  response : McpTransportResponse,
) -> Result[McpTransportPayload, McpProtocolError] {
  if response.status_code == 202 {
    return Ok(McpTransportPayload::AcceptedNoContent)
  }
  if response.status_code != 200 {
    return Err(McpProtocolError::InvalidResponse("unexpected transport status"))
  }
  let content_type = response.content_type.unwrap_or_default().to_lower()
  if content_type.contains("text/event-stream") {
    match decode_sse_data(response.body).get(0) {
      Some(payload) => {
        let json = @json.parse(payload) catch {
          _ => return Err(McpProtocolError::InvalidResponse("invalid sse json"))
        }
        Ok(McpTransportPayload::JsonPayload(json))
      }
      None => Err(McpProtocolError::InvalidResponse("missing sse data"))
    }
  } else {
    let json = @json.parse(response.body) catch {
      _ => return Err(McpProtocolError::InvalidResponse("invalid json body"))
    }
    Ok(McpTransportPayload::JsonPayload(json))
  }
}

///|
pub fn expect_json_payload(
  payload : McpTransportPayload,
) -> Json raise McpProtocolError {
  match payload {
    JsonPayload(json) => json
    AcceptedNoContent =>
      raise McpProtocolError::InvalidResponse("expected json payload")
  }
}
