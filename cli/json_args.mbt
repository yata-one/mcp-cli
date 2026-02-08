///|
/// Parsing helper for tool call arguments.

///|
suberror JsonArgsError {
  InvalidJson(String)
  ArgsMustBeObject
}

///|
pub impl Show for JsonArgsError with output(self, logger) {
  match self {
    InvalidJson(msg) => {
      logger.write_string("InvalidJson(\"")
      logger.write_string(msg)
      logger.write_string("\")")
    }
    ArgsMustBeObject => logger.write_string("ArgsMustBeObject")
  }
}

///|
pub fn parse_json_args(text : String) -> Json raise JsonArgsError {
  let trimmed = text.trim().to_string()
  if trimmed.is_empty() {
    return Json::object({})
  }
  let json = @json.parse(trimmed) catch {
    err => raise JsonArgsError::InvalidJson(err.to_string())
  }
  match json {
    Object(_) => json
    _ => raise JsonArgsError::ArgsMustBeObject
  }
}
