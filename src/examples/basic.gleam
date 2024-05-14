//
//  Run this example with `gleam run -m chrobot/examples/basic`
// 

import chrobot
import gleam/erlang/process
import gleam/result

pub fn main() {
  let assert Ok(browser) = chrobot.launch()
  let assert Ok(page) =
    browser
    |> chrobot.open("https://example.com", 60_000)

  process.sleep(1000)

  let assert Ok(file) = chrobot.pdf(page)
  let assert Ok(_) = chrobot.to_file(file, "test_print")
  let assert Ok(_) = chrobot.quit(browser)
}
