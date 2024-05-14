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
    |> chrobot.open("https://gleam.run", 10_000)

  process.sleep(500)

  let assert Ok(screenshot) = chrobot.screenshot(page)
  let assert Ok(_) = chrobot.to_file(screenshot, "test_screnshot.png")
  let assert Ok(_) = chrobot.quit(browser)
}
