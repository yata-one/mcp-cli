///|
pub fn load_credentials_file_or_empty(
  path : String,
) -> @auth.CredentialsFile raise {
  if @fs.path_exists(path) {
    let content = @fs.read_file_to_string(path)
    @auth.decode_credentials_file(@json.parse(content))
  } else {
    @auth.empty_credentials_file()
  }
}

///|
pub fn save_credentials_file(
  path : String,
  file : @auth.CredentialsFile,
) -> Unit raise {
  secure_write_private_atomic(path, file.to_json().stringify())
}

///|
pub fn credentials_file_mode(path : String) -> Int raise {
  secure_file_mode(path)
}
