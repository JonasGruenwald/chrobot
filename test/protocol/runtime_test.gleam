import birdie
import chrobot/chrome
import chrobot/protocol/runtime
import gleam/dynamic
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import simplifile as file

/// This module havs some types with dynamic values.
/// We can't currently encode them, which could lead to confusion,
/// encoders also don't have a failure mode, so we can't return an error.
/// We should ensure a message is logged to stdio when this happens.
pub fn enocde_dynamic_test() {
  // We can't assert that it actually logs, but we can **hope**
  runtime.encode__call_argument(runtime.CallArgument(
    value: Some(dynamic.from("My dynamic value")),
    unserializable_value: None,
    object_id: Some(runtime.RemoteObjectId("1")),
  ))
  |> json.to_string()
  |> birdie.snap("Enocded CallArgument with dynamic value")
}

pub fn evaluate_test() {
  let mock_callback = fn(method, params: Option(json.Json)) -> Result(
    dynamic.Dynamic,
    chrome.RequestError,
  ) {
    method
    |> should.equal("Runtime.evaluate")

    params
    |> should.be_some()
    |> json.to_string()
    |> birdie.snap("Runtime.evaluate params")

    let assert Ok(response_file) =
      file.read("test_assets/runtime_evaluate_response.json")
    let assert Ok(response) = json.decode(response_file, dynamic.dynamic)

    Ok(response)
  }

  runtime.evaluate(
    mock_callback,
    expression: "document.querySelector(\"h1\")",
    object_group: None,
    include_command_line_api: None,
    silent: Some(False),
    context_id: None,
    return_by_value: Some(True),
    user_gesture: Some(True),
    await_promise: Some(False),
  )
  |> string.inspect()
  |> birdie.snap("Runtime.evaluate response")
}
