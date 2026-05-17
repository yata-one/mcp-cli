///|
#cfg(all(target="native", not(platform="windows")))
async test "oauth callback: captures code with matching state" {
  let result = wait_for_oauth_callback(
    port=0,
    path="/callback",
    expected_state="state-1",
    timeout_ms=1000,
    trigger=redirect_uri => {
      ignore(@http.get(redirect_uri + "?code=code-1&state=state-1"))
    },
  )
  inspect(result.code + ":" + result.state, content="code-1:state-1")
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "oauth callback: rejects mismatched state" {
  let result : Result[OAuthCallbackCode, OAuthCallbackError] = try? wait_for_oauth_callback(
    port=0,
    path="/callback",
    expected_state="state-1",
    timeout_ms=1000,
    trigger=redirect_uri => {
      ignore(@http.get(redirect_uri + "?code=code-1&state=wrong"))
    },
  )
  @debug.debug_inspect(result, content="Err(StateMismatch)")
}
