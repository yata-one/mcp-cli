///|
/// Minimal SSE parser for Streamable HTTP transport.
///
/// We only extract `data:` fields and return one payload string per SSE event.
/// Multiple `data:` lines in one event are joined with `\n` (per SSE spec).

///|
pub fn decode_sse_data(text : String) -> Array[String] {
  let normalized = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let out = []
  let data_lines = []
  for line_view in normalized.split("\n") {
    let line = line_view.to_string()
    if line.is_empty() {
      if !data_lines.is_empty() {
        out.push(data_lines.join("\n"))
        data_lines.clear()
      }
    } else if line.has_prefix("data:") {
      let mut rest = line.view(start_offset=5).to_string()
      if rest.has_prefix(" ") {
        rest = rest.view(start_offset=1).to_string()
      }
      data_lines.push(rest)
    } else {
      ()
    }
  }
  if !data_lines.is_empty() {
    out.push(data_lines.join("\n"))
  }
  out
}
