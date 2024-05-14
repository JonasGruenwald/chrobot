import gleam/erlang/process.{type CallError, type Subject} as p
import gleam/json
import gleam/option

pub fn add_optional(
  prop_encoders: List(#(String, json.Json)),
  value: option.Option(a),
  callback: fn(a) -> #(String, json.Json),
) {
  case value {
    option.Some(a) -> [callback(a), ..prop_encoders]
    option.None -> prop_encoders
  }
}

pub fn try_call_with_subject(
  subject: Subject(request),
  make_request: fn(Subject(response)) -> request,
  reply_subject: Subject(response),
  within timeout: Int,
) -> Result(response, CallError(response)) {
  // Monitor the callee process so we can tell if it goes down (meaning we
  // won't get a reply)
  let monitor = p.monitor_process(p.subject_owner(subject))

  // Send the request to the process over the channel
  p.send(subject, make_request(reply_subject))

  // Await a reply or handle failure modes (timeout, process down, etc)
  let result =
    p.new_selector()
    |> p.selecting(reply_subject, Ok)
    |> p.selecting_process_down(monitor, fn(down: p.ProcessDown) {
      Error(p.CalleeDown(reason: down.reason))
    })
    |> p.select(timeout)

  // Demonitor the process and close the channels as we're done
  p.demonitor_process(monitor)

  // Prepare an appropriate error (if present) for the caller
  case result {
    Error(Nil) -> Error(p.CallTimeout)
    Ok(res) -> res
  }
}
