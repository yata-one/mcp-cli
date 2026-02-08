///|
test "decode_sse_data: single event" {
  let text = "data: {\"x\":1}\n\n"
  inspect(decode_sse_data(text), content="[\"{\\\"x\\\":1}\"]")
}

///|
test "decode_sse_data: multiple events + multiline data" {
  let text =
    #|event: message
    #|data: line1
    #|data: line2
    #|
    #|data: {"y":2}
    #|
  inspect(
    decode_sse_data(text),
    content="[\"line1\\nline2\", \"{\\\"y\\\":2}\"]",
  )
}
