///|
test "auth host actions: first step reads credentials file" {
  let action = credentials_lookup_action(
    credentials_path="/home/me/.config/mcpx/credentials.json",
  )
  inspect(
    action.to_json().stringify(),
    content=(
      #|{"kind":"read_text_file","path":"/home/me/.config/mcpx/credentials.json"}
    ),
  )
}

///|
test "auth host actions: stores refreshed credentials with private atomic write" {
  let file = put_credentials_entry(
    empty_credentials_file(),
    "github|abcd",
    credentials_entry(
      server_name="github",
      server_url=Some("https://mcp.github.com/mcp"),
      client_id=Some("client-1"),
      access_token="access-1",
      refresh_token=Some("refresh-1"),
      expires_at=Some(2000),
      updated_at="2026-05-16T00:00:00.000Z",
    ),
  )
  let action = credentials_write_action(
    credentials_path="/home/me/.config/mcpx/credentials.json",
    file,
  )
  inspect(
    action.to_json().stringify(),
    content=(
      #|{"kind":"write_text_file","path":"/home/me/.config/mcpx/credentials.json","contents":"{\"entries\":{\"github|abcd\":{\"serverName\":\"github\",\"serverUrl\":\"https://mcp.github.com/mcp\",\"clientInfo\":{\"client_id\":\"client-1\"},\"tokens\":{\"access_token\":\"access-1\",\"refresh_token\":\"refresh-1\",\"token_type\":\"Bearer\",\"expires_at\":2000},\"updatedAt\":\"2026-05-16T00:00:00.000Z\"}},\"version\":1}","mode":384,"atomic":true,"createParentDirs":true}
    ),
  )
}

///|
test "auth host actions: cached valid token becomes bearer header" {
  let entry = credentials_entry(
    server_name="github",
    access_token="access-1",
    refresh_token=Some("refresh-1"),
    expires_at=Some(2000),
    updated_at="2026-05-16T00:00:00.000Z",
  )
  @debug.debug_inspect(
    decide_auth_cache(Some(entry), now_seconds=1000, skew_seconds=300),
    content="UseBearerHeader(\"Bearer access-1\")",
  )
}

///|
test "auth host actions: near-expiry token with refresh token requests refresh" {
  let entry = credentials_entry(
    server_name="github",
    access_token="access-1",
    refresh_token=Some("refresh-1"),
    expires_at=Some(1200),
    updated_at="2026-05-16T00:00:00.000Z",
  )
  @debug.debug_inspect(
    decide_auth_cache(Some(entry), now_seconds=1000, skew_seconds=300),
    content="RefreshWithToken(\"refresh-1\")",
  )
}

///|
test "auth host actions: missing cache requires explicit auth" {
  @debug.debug_inspect(
    decide_auth_cache(None, now_seconds=1000, skew_seconds=300),
    content="ReauthRequired",
  )
}
