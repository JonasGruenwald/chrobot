////
////  Run this example with `gleam run -m chrobot/examples/basic`
//// 

import chrome
import gleam/erlang/process
import gleam/io
import gleam/option as o
import protocol/target

pub fn main() {
  let assert Ok(browser_subject) = chrome.launch()
  io.print("Browser launched ")
  let assert Ok(target_response) =
    target.create_target(
      browser_subject,
      "https://gleam.run/",
      o.Some(500),
      o.Some(500),
      o.Some(True),
      o.Some(False),
    )
  io.debug(#("Target created ", target_response.target_id))
  process.sleep(5000)
  let assert Ok(_) = chrome.quit(browser_subject)
}
