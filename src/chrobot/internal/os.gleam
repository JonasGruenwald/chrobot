/// OS family type representing the major operating system categories
pub type OsFamily {
  Darwin
  Linux
  WindowsNt
  FreeBsd
  Other
}

/// Get the current operating system family
pub fn family() -> OsFamily {
  case get_os_type() {
    #("unix", "darwin") -> Darwin
    #("unix", "linux") -> Linux
    #("unix", "freebsd") -> FreeBsd
    #("win32", _) -> WindowsNt
    _ -> Other
  }
}

@external(erlang, "chrobot_ffi", "get_os_type")
fn get_os_type() -> #(String, String)
