///|
test "credentials: empty file encodes version and entries" {
  inspect(
    empty_credentials_file().to_json().stringify(),
    content="{\"entries\":{},\"version\":1}",
  )
}

///|
test "credentials: stores server entry keyed by name and transport hash" {
  let file = empty_credentials_file()
  let entry = credentials_entry(
    server_name="github",
    server_url=Some("https://mcp.github.com/mcp"),
    client_id=Some("client-1"),
    access_token="access-1",
    refresh_token=Some("refresh-1"),
    expires_at=Some(2000),
    updated_at="2026-05-16T00:00:00.000Z",
  )
  let next = put_credentials_entry(file, "github|abcd", entry)
  inspect(
    next.to_json().stringify(),
    content=(
      #|{"entries":{"github|abcd":{"serverName":"github","serverUrl":"https://mcp.github.com/mcp","clientInfo":{"client_id":"client-1"},"tokens":{"access_token":"access-1","refresh_token":"refresh-1","token_type":"Bearer","expires_at":2000},"updatedAt":"2026-05-16T00:00:00.000Z"}},"version":1}
    ),
  )
}

///|
test "credentials: decodes encoded file roundtrip" {
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
  let decoded = decode_credentials_file(file.to_json())
  @debug.debug_inspect(
    decoded,
    content=(
      #|{
      #|  version: 1,
      #|  entries: {
      #|    "github|abcd": {
      #|      server_name: "github",
      #|      server_url: Some("https://mcp.github.com/mcp"),
      #|      client_info: Some({ client_id: "client-1" }),
      #|      tokens: {
      #|        access_token: "access-1",
      #|        refresh_token: Some("refresh-1"),
      #|        expires_at: Some(2000),
      #|      },
      #|      updated_at: "2026-05-16T00:00:00.000Z",
      #|    },
      #|  },
      #|  pending_oauth: {},
      #|}
    ),
  )
}

///|
test "credentials: finds entry by server name and exact url before fallback" {
  let file = put_credentials_entry(
    empty_credentials_file(),
    "github|old",
    credentials_entry(
      server_name="github",
      server_url=Some("https://old.example/mcp"),
      access_token="old-token",
      updated_at="2026-05-16T00:00:00.000Z",
    ),
  )
  let file = put_credentials_entry(
    file,
    "github|current",
    credentials_entry(
      server_name="github",
      server_url=Some("https://mcp.github.com/mcp"),
      access_token="current-token",
      updated_at="2026-05-16T00:00:00.000Z",
    ),
  )
  let token = match
    find_credentials_entry(
      file,
      server_name="github",
      server_url=Some("https://mcp.github.com/mcp"),
    ) {
    Some(entry) => entry.tokens.access_token
    None => "missing"
  }
  inspect(token, content="current-token")
}

///|
test "credentials: stores pending OAuth flow by server and state" {
  let file = put_pending_oauth_flow(
    empty_credentials_file(),
    pending_oauth_flow(
      server_name="github",
      server_url=Some("https://mcp.github.com/mcp"),
      client_id="client-1",
      client_secret=Some("secret-1"),
      token_endpoint="https://auth.example/token",
      redirect_uri="http://127.0.0.1:8765/callback",
      code_verifier="verifier-1",
      state="state-1",
      created_at="1000",
    ),
  )
  inspect(
    file.to_json().stringify(),
    content=(
      #|{"entries":{},"version":1,"pendingOAuth":{"github|state-1":{"serverName":"github","serverUrl":"https://mcp.github.com/mcp","clientInfo":{"client_id":"client-1","client_secret":"secret-1"},"tokenEndpoint":"https://auth.example/token","redirectUri":"http://127.0.0.1:8765/callback","codeVerifier":"verifier-1","state":"state-1","createdAt":"1000"}}}
    ),
  )
  let decoded = decode_credentials_file(file.to_json())
  let found = find_pending_oauth_flow(
    decoded,
    server_name="github",
    state="state-1",
  )
  @debug.debug_inspect(
    found.map(flow => (flow.client_info.client_id, flow.code_verifier)),
    content=(
      #|Some(("client-1", "verifier-1"))
    ),
  )
}

///|
test "credentials: removes pending OAuth flow after exchange" {
  let file = put_pending_oauth_flow(
    empty_credentials_file(),
    pending_oauth_flow(
      server_name="github",
      client_id="client-1",
      token_endpoint="https://auth.example/token",
      redirect_uri="http://127.0.0.1:8765/callback",
      code_verifier="verifier-1",
      state="state-1",
      created_at="1000",
    ),
  )
  let next = remove_pending_oauth_flow(
    file,
    server_name="github",
    state="state-1",
  )
  inspect(next.to_json().stringify(), content="{\"entries\":{},\"version\":1}")
}
