//
//  Run this example with `gleam run -m chrobot/examples/basic`
// 

import chrobot
import chrome
import gleam/erlang/process
import gleam/io
import gleam/json
import gleam/option as o
import protocol/dom
import protocol/target

pub fn main() {
  let assert Ok(browser_subject) = chrobot.launch()
  use <- chrome.defer_quit(browser_subject)
  io.print("Browser launched ")
  let assert Ok(target_response) =
    target.create_target(
      browser_subject,
      o.None,
      "https://example.com",
      o.None,
      o.None,
      o.None,
      o.None,
    )
  let assert Ok(attach_response) =
    target.attach_to_target(
      browser_subject,
      o.None,
      target_response.target_id,
      o.Some(True),
    )
  io.debug(#(
    "Attached to target ",
    target_response.target_id,
    attach_response.session_id,
  ))
  let assert target.AttachToTargetResponse(target.SessionID(session_id)) =
    attach_response
  process.sleep(2000)

  let assert Ok(res) =
    dom.get_document(browser_subject, o.Some(session_id), o.None, o.None)

    io.debug(res)
}
