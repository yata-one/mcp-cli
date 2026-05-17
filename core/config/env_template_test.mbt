///|
test "env template: resolves ${VAR} from provided env" {
  inspect(
    resolve_env_template("Bearer ${TOKEN}", { "TOKEN": "abc" }),
    content="Bearer abc",
  )
}

///|
test "env template: missing var raises in strict mode" {
  let result : Result[String, EnvTemplateError] = try? resolve_env_template(
    "Bearer ${TOKEN}",
    {},
  )
  @debug.debug_inspect(result, content="Err(MissingEnvVar(\"TOKEN\"))")
}

///|
test "env template: non-strict missing var becomes empty" {
  inspect(
    resolve_env_template("Bearer ${TOKEN}", {}, strict=false),
    content="Bearer ",
  )
}

///|
test "env template: rejects fallback syntax because only ${VAR} is supported" {
  let result : Result[String, EnvTemplateError] = try? resolve_env_template(
    "${TOKEN:-fallback}",
    { "TOKEN": "abc" },
  )
  @debug.debug_inspect(
    result,
    content="Err(InvalidEnvVarSyntax(\"${TOKEN:-fallback}\"))",
  )
}

///|
test "env template: rejects empty placeholder" {
  let result : Result[String, EnvTemplateError] = try? resolve_env_template(
    "${}",
    {},
  )
  @debug.debug_inspect(result, content="Err(InvalidEnvVarSyntax(\"${}\"))")
}
