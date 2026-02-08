///|
/// Daemon state file utilities (port discovery).

///|
suberror StateError {
  WriteFailed(String)
}

///|
pub impl Show for StateError with output(self, logger) {
  match self {
    WriteFailed(msg) => {
      logger.write_string("WriteFailed(\"")
      logger.write_string(msg)
      logger.write_string("\")")
    }
  }
}

///|
pub fn state_path() -> String {
  let base = match @sys.get_env_var("HOME") {
    Some(home) => home
    None => "."
  }
  @path.Path(base)
  .join(@path.Path(".agents"))
  .join(@path.Path("mcp-cli-daemon.json"))
  .to_string()
}

///|
pub fn read_port(path : String) -> Int? {
  if !@fs.path_exists(path) {
    return None
  }
  let text = @fs.read_file_to_string(path) catch { _ => return None }
  let json = @json.parse(text) catch { _ => return None }
  match json {
    Object(o) =>
      match o.get("port") {
        Some(Number(d, ..)) => Some(d.to_int())
        _ => None
      }
    _ => None
  }
}

///|
pub fn write_port(path : String, port : Int) -> Unit raise StateError {
  let dir = @path.Path(path).dirname().to_string()
  if !@fs.path_exists(dir) {
    @fs.create_dir(dir) catch {
      _ => ()
    }
  }
  let json = Json::object({ "port": Json::number(port.to_double()) })
  @fs.write_string_to_file(path, json.stringify(indent=2)) catch {
    err => raise StateError::WriteFailed(err.to_string())
  }
}
