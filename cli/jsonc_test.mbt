///|
test "normalize: strips line comments" {
  let input =
    #|{
    #|  "a": 1, // comment
    #|  "b": 2
    #|}
  let normalized = normalize(input)
  let parsed = @json.parse(normalized)
  let expected =
    #|{
    #|  "a": 1,
    #|  "b": 2
    #|}
  inspect(parsed.stringify(indent=2), content=expected)
}

///|
test "normalize: strips block comments (preserve newlines)" {
  let input =
    #|{
    #|  /* header
    #|     comment */
    #|  "a": 1
    #|}
  let normalized = normalize(input)
  let parsed = @json.parse(normalized)
  let expected =
    #|{
    #|  "a": 1
    #|}
  inspect(parsed.stringify(indent=2), content=expected)
}

///|
test "normalize: does not treat comment markers inside strings as comments" {
  let input =
    #|{
    #|  "url": "https://example.com/a//b",
    #|  "x": "/* not a comment */"
    #|}
  let normalized = normalize(input)
  let parsed = @json.parse(normalized)
  let expected =
    #|{
    #|  "url": "https://example.com/a//b",
    #|  "x": "/* not a comment */"
    #|}
  inspect(parsed.stringify(indent=2), content=expected)
}

///|
test "normalize: removes trailing commas in objects and arrays" {
  let input =
    #|{
    #|  "a": [1, 2,],
    #|  "b": { "x": 1, },
    #|}
  let normalized = normalize(input)
  let parsed = @json.parse(normalized)
  let expected =
    #|{
    #|  "a": [
    #|    1,
    #|    2
    #|  ],
    #|  "b": {
    #|    "x": 1
    #|  }
    #|}
  inspect(parsed.stringify(indent=2), content=expected)
}
