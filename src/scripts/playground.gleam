import simplifile as file
import gleam/io

pub fn main() {
  let assert Ok(files) = file.get_files("chrome")
  io.debug(files)
}
