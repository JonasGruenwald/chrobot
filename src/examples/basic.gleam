//
//  Run this example with `gleam run -m chrobot/examples/raw_protocol_calls`
// 

import chrobot
import gleam/io

pub fn main() {
  let assert Ok(browser) = chrobot.launch()
  use <- chrobot.defer_quit(browser)

  let assert Ok(page) =
    browser
    |> chrobot.open("http://example.com", 10_000)

    io.debug(page.root_node)
}
