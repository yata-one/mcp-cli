///|
suberror JsoncError {
  UnterminatedBlockComment
  UnterminatedString
}

///|
pub fn normalize(input : String) -> String raise JsoncError {
  let no_comments = strip_comments(input)
  strip_trailing_commas(no_comments)
}

///|
fn strip_comments(input : String) -> String raise JsoncError {
  let view = input.to_string_view()
  let sb = StringBuilder::new(size_hint=view.length())
  for i = 0, state = CommentState::Code, escape = false; i < view.length(); {
    let c = view.get_char(i).unwrap()
    match state {
      CommentState::Code =>
        if c == '"' {
          sb.write_char(c)
          continue i + 1, CommentState::InString, false
        } else if c == '/' {
          let next = view.get_char(i + 1)
          match next {
            Some('/') => continue i + 2, CommentState::LineComment, false
            Some('*') => continue i + 2, CommentState::BlockComment, false
            _ => {
              sb.write_char(c)
              continue i + 1, state, false
            }
          }
        } else {
          sb.write_char(c)
          continue i + 1, state, false
        }
      CommentState::InString =>
        if escape {
          sb.write_char(c)
          continue i + 1, state, false
        } else if c == '\\' {
          sb.write_char(c)
          continue i + 1, state, true
        } else if c == '"' {
          sb.write_char(c)
          continue i + 1, CommentState::Code, false
        } else {
          sb.write_char(c)
          continue i + 1, state, false
        }
      CommentState::LineComment =>
        if c == '\n' {
          // Preserve newlines to keep line numbers stable.
          sb.write_char(c)
          continue i + 1, CommentState::Code, false
        } else {
          continue i + 1, state, false
        }
      CommentState::BlockComment =>
        if c == '\n' {
          sb.write_char(c)
          continue i + 1, state, false
        } else if c == '*' {
          let next = view.get_char(i + 1)
          match next {
            Some('/') => continue i + 2, CommentState::Code, false
            _ => continue i + 1, state, false
          }
        } else {
          continue i + 1, state, false
        }
    }
  } nobreak {
    match state {
      CommentState::BlockComment => raise JsoncError::UnterminatedBlockComment
      CommentState::InString => raise JsoncError::UnterminatedString
      _ => ()
    }
    sb.to_string()
  }
}

///|
fn strip_trailing_commas(input : String) -> String raise JsoncError {
  let view = input.to_string_view()
  let sb = StringBuilder::new(size_hint=view.length())
  for i = 0, in_string = false, escape = false; i < view.length(); {
    let c = view.get_char(i).unwrap()
    if in_string {
      sb.write_char(c)
      if escape {
        continue i + 1, in_string, false
      } else if c == '\\' {
        continue i + 1, in_string, true
      } else if c == '"' {
        continue i + 1, false, false
      } else {
        continue i + 1, in_string, false
      }
    } else if c == '"' {
      sb.write_char(c)
      continue i + 1, true, false
    } else if c == ',' {
      if is_trailing_comma(view, i) {
        continue i + 1, in_string, false
      } else {
        sb.write_char(c)
        continue i + 1, in_string, false
      }
    } else {
      sb.write_char(c)
      continue i + 1, in_string, false
    }
  } nobreak {
    if in_string {
      raise JsoncError::UnterminatedString
    }
    sb.to_string()
  }
}

///|
fn is_trailing_comma(view : StringView, comma_index : Int) -> Bool {
  let len = view.length()
  for j = comma_index + 1; j < len; j = j + 1 {
    let c = view.get_char(j).unwrap()
    match c {
      ' ' | '\t' | '\r' | '\n' => ()
      ']' | '}' => break true
      _ => break false
    }
  } nobreak {
    false
  }
}

///|
priv enum CommentState {
  Code
  InString
  LineComment
  BlockComment
}
