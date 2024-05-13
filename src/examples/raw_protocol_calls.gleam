//
//  Run this example with `gleam run -m chrobot/examples/raw_protocol_calls`
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
  use <- chrobot.defer_quit(browser_subject)
  let caller = fn(method, params) {
    chrome.call(browser_subject, method, params, o.None, 1000)
  }
  io.print("Browser launched ")
  let assert Ok(target_response) =
    target.create_target(
      caller,
      "https://example.com",
      o.None,
      o.None,
      o.None,
      o.None,
    )
  let assert Ok(attach_response) =
    target.attach_to_target(caller, target_response.target_id, o.Some(True))
  io.debug(#(
    "Attached to target ",
    target_response.target_id,
    attach_response.session_id,
  ))
  let assert target.AttachToTargetResponse(target.SessionID(session_id)) =
    attach_response

  let session_caller = fn(method, params) {
    chrome.call(browser_subject, method, params, o.Some(session_id), 1000)
  }

  process.sleep(2000)

  let assert Ok(res) = dom.get_document(session_caller, o.None, o.None)

  let assert Ok(res) =
    dom.get_outer_html(session_caller, o.Some(res.root.node_id), o.None, o.None)

  io.debug(res.outer_html)
}
