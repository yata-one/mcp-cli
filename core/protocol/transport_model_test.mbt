///|
test "mcp client transport model: normalizes json sse and accepted payloads" {
  let json_response = mcp_transport_response(
    status_code=200,
    content_type=Some("application/json"),
    body="{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}",
  )
  @debug.debug_inspect(
    decode_mcp_transport_payload(json_response),
    content=(
      #|Ok(JsonPayload(Object({ "jsonrpc": String("2.0"), "id": Number(1), "result": Object({}) })))
    ),
  )
  let sse_response = mcp_transport_response(
    status_code=200,
    content_type=Some("text/event-stream"),
    body="data: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"ok\":true}}\n\n",
  )
  @debug.debug_inspect(
    decode_mcp_transport_payload(sse_response),
    content=(
      #|Ok(
      #|  JsonPayload(
      #|    Object(
      #|      {
      #|        "jsonrpc": String("2.0"),
      #|        "id": Number(2),
      #|        "result": Object({ "ok": True }),
      #|      },
      #|    ),
      #|  ),
      #|)
    ),
  )
  @debug.debug_inspect(
    decode_mcp_transport_payload(
      mcp_transport_response(status_code=202, content_type=None, body=""),
    ),
    content="Ok(AcceptedNoContent)",
  )
}
