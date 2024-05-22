import gleam/erlang/process.{type CallError, type Subject} as p
import gleam/io
import gleam/json
import gleam/option
import gleam/string
import gleam_community/ansi

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

pub fn alert_encode_dynamic(input_value) {
  warn(
    "You passed a dymamic value to a protocol encoder!
Dynamic values cannot be encoded, the value will be set to null instead.
This is unlikely to be intentional, you should fix that part of your code.",
  )
  io.println("The value was: " <> string.inspect(input_value))
  json.null()
}

fn align(content: String) {
  string.replace(content, "\n", "\n            ")
}

pub fn err(content: String) {
  {
    "[-_-] ERR! "
    |> ansi.bg_red()
    |> ansi.white()
    |> ansi.bold()
    <> " "
    <> align(content)
    |> ansi.red()
  }
  |> io.println()
}

pub fn warn(content: String) {
  {
    "[O_O] HEY! "
    |> ansi.bg_yellow()
    |> ansi.black()
    |> ansi.bold()
    <> " "
    <> align(content)
    |> ansi.yellow()
  }
  |> io.println()
}

pub fn hint(content: String) {
  {
    "[>‿0] HINT "
    |> ansi.bg_cyan()
    |> ansi.black()
    |> ansi.bold()
    <> " "
    <> align(content)
    |> ansi.cyan()
  }
  |> io.println()
}

pub fn info(content: String) {
  {
    "[0‿0] INFO "
    |> ansi.bg_white()
    |> ansi.black()
    |> ansi.bold()
    <> " "
    <> align(content)
    |> ansi.white()
  }
  |> io.println()
}

pub fn show_cmd(content: String) {
  { "\n " <> ansi.dim("$") <> " " <> ansi.bold(content) <> "\n" }
  |> io.println()
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
