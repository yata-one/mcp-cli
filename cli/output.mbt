///|
/// Human-readable output formatting.

///|
pub struct ToolView {
  name : String
  description : String?
  input_schema : Json
} derive(Show)

///|
pub fn tool_view(
  name : String,
  description? : String,
  input_schema? : Json,
) -> ToolView {
  { name, description, input_schema: input_schema.unwrap_or_default() }
}

///|
pub struct ServerView {
  name : String
  tools : Array[ToolView]
  instructions : String?
} derive(Show)

///|
pub fn server_view(
  name : String,
  tools : Array[ToolView],
  instructions? : String,
) -> ServerView {
  { name, tools, instructions }
}

///|
pub fn format_server_list(servers : Array[ServerView]) -> String {
  let lines = []
  for server in servers {
    lines.push(server.name)
    match server.instructions {
      None => ()
      Some(text) => {
        let first_line = match text.find("\n") {
          None => text
          Some(i) => text.view(end_offset=i).to_string()
        }
        lines.push("  Instructions: " + first_line)
      }
    }
    for tool in server.tools {
      match tool.description {
        None => lines.push("  • " + tool.name)
        Some(desc) => lines.push("  • " + tool.name + " - " + desc)
      }
    }
    lines.push("")
  }
  lines.join("\n").trim_end().to_string()
}

///|
pub fn format_search_results(results : Array[(String, ToolView)]) -> String {
  let blocks = results
    .map(fn(pair) {
      let (server, tool) = pair
      let name = server + "/" + tool.name
      match tool.description {
        None => name
        Some(desc) => name + ": " + desc
      }
    })
    .join("\n\n")
  "List grep results (<server>/<tool> in detail):\n\n" + blocks
}

///|
pub fn format_tool_schema(server_name : String, tool : ToolView) -> String {
  let lines = []
  lines.push("Tool: " + tool.name)
  lines.push("Server: " + server_name)
  lines.push("")
  match tool.description {
    None => ()
    Some(desc) => {
      lines.push("Description:")
      lines.push("  " + desc)
      lines.push("")
    }
  }
  lines.push("Input Schema:")
  lines.push(tool.input_schema.stringify(indent=2))
  lines.join("\n")
}

///|
pub fn format_server_details(
  server_name : String,
  server : ServerConfig,
  tools : Array[ToolView],
  instructions : String?,
) -> String {
  let lines = []
  lines.push("Server: " + server_name)
  match server.transport {
    Transport::Http(url, _) => {
      lines.push("Transport: HTTP")
      lines.push("URL: " + url)
    }
    Transport::Stdio(command, args, _, _) => {
      lines.push("Transport: stdio")
      lines.push("Command: " + command + " " + args.join(" "))
    }
  }
  match instructions {
    None => ()
    Some(text) => {
      lines.push("")
      lines.push("Instructions:")
      lines.append(indent_lines(text, "  "))
    }
  }
  lines.push("")
  lines.push("Tools (" + tools.length().to_string() + "):")
  for tool in tools {
    lines.push("  " + tool.name)
    match tool.description {
      None => ()
      Some(desc) => lines.push("    " + desc)
    }
    let params = format_schema_parameters(tool.input_schema)
    if !params.is_empty() {
      lines.push("    Parameters:")
      for p in params {
        lines.push("      • " + p)
      }
    }
    lines.push("")
  }
  lines.join("\n").trim_end().to_string()
}

///|
pub fn format_tool_result(result : Json) -> String {
  let texts = extract_text_parts(result)
  if texts.is_empty() {
    result.stringify(indent=2)
  } else {
    texts.join("\n")
  }
}

///|
fn extract_text_parts(result : Json) -> Array[String] {
  let items = match result {
    Object(o) =>
      match o.get("content") {
        Some(Array(arr)) => arr
        _ => []
      }
    _ => []
  }
  items.filter_map(fn(item) {
    match item {
      Object(o) =>
        match (o.get("type"), o.get("text")) {
          (Some(String("text")), Some(String(text))) => Some(text)
          _ => None
        }
      _ => None
    }
  })
}

///|
fn indent_lines(text : String, prefix : String) -> Array[String] {
  text.split("\n").map(line => prefix + line.to_string()).to_array()
}

///|
fn format_schema_parameters(schema : Json) -> Array[String] {
  let (required, properties) = match schema {
    Object(o) => (decode_required(o), decode_properties(o))
    _ => ([], [])
  }
  properties.map(fn(pair) {
    let (name, prop) = pair
    let (typ, desc) = decode_prop(prop)
    let req = if required.contains(name) { "required" } else { "optional" }
    let base = name + " (" + typ + ", " + req + ")"
    match desc {
      None => base
      Some(d) => base + " - " + d
    }
  })
}

///|
fn decode_required(schema : Map[String, Json]) -> Array[String] {
  match schema.get("required") {
    Some(Array(items)) =>
      items.filter_map(fn(x) {
        match x {
          String(s) => Some(s)
          _ => None
        }
      })
    _ => []
  }
}

///|
fn decode_properties(schema : Map[String, Json]) -> Array[(String, Json)] {
  match schema.get("properties") {
    Some(Object(props)) => props.to_array()
    _ => []
  }
}

///|
fn decode_prop(prop : Json) -> (String, String?) {
  match prop {
    Object(o) => {
      let typ = match o.get("type") {
        Some(String(s)) => s
        _ => "any"
      }
      let desc = match o.get("description") {
        Some(String(s)) => Some(s)
        _ => None
      }
      (typ, desc)
    }
    _ => ("any", None)
  }
}
