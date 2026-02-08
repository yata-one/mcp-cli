///|
/// Tool filtering utilities (glob patterns) compatible with upstream `mcp-cli`.
///
/// Patterns:
/// - `*` matches any sequence of characters (including empty)
/// - `?` matches exactly one character
/// - Matching is ASCII case-insensitive (tool names are typically ASCII)

///|
pub fn matches_pattern(name : String, pattern : String) -> Bool {
  let n = name.to_array()
  let p = pattern.to_array()
  let mut i = 0
  let mut j = 0
  let mut star_j = -1
  let mut star_i = 0
  while i < n.length() {
    if j < p.length() {
      let pc = p[j]
      if pc == '*' {
        star_j = j
        star_i = i
        j = j + 1
      } else if pc == '?' || char_eq_ci(n[i], pc) {
        i = i + 1
        j = j + 1
      } else if star_j != -1 {
        j = star_j + 1
        star_i = star_i + 1
        i = star_i
      } else {
        return false
      }
    } else if star_j != -1 {
      j = star_j + 1
      star_i = star_i + 1
      i = star_i
    } else {
      return false
    }
  }
  while j < p.length() && p[j] == '*' {
    j = j + 1
  }
  j == p.length()
}

///|
pub fn matches_any_pattern(name : String, patterns : Array[String]) -> Bool {
  patterns.any(p => matches_pattern(name, p))
}

///|
pub fn is_tool_allowed(tool_name : String, server : ServerConfig) -> Bool {
  if !server.disabled_tools.is_empty() &&
    matches_any_pattern(tool_name, server.disabled_tools) {
    return false
  }
  if !server.allowed_tools.is_empty() {
    return matches_any_pattern(tool_name, server.allowed_tools)
  }
  true
}

///|
pub fn filter_tool_names(
  names : Array[String],
  server : ServerConfig,
) -> Array[String] {
  names.filter(n => is_tool_allowed(n, server))
}

///|
fn char_eq_ci(a : Char, b : Char) -> Bool {
  if a.is_ascii() && b.is_ascii() {
    a.to_ascii_lowercase() == b.to_ascii_lowercase()
  } else {
    a == b
  }
}
