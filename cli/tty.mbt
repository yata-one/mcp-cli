///|
/// Small native helper to detect whether stdin is a TTY.

///|
#cfg(target="native")
extern "C" fn isatty(fd : Int) -> Int = "isatty"

///|
#cfg(target="native")
pub fn stdin_is_tty() -> Bool {
  isatty(@stdio.stdin.fd()) != 0
}

///|
#cfg(not(target="native"))
pub fn stdin_is_tty() -> Bool {
  true
}
