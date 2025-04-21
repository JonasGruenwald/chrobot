import envoy
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process.{type CallError, type Subject} as p
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam_community/ansi
import spinner

/// Very very naive but should be fine
fn term_supports_color() -> Bool {
  case envoy.get("TERM") {
    Ok("dumb") -> False
    _ -> True
  }
}

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
  case term_supports_color() {
    True -> {
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
    False -> {
      io.println("[-_-] ERR! " <> content)
    }
  }
}

pub fn warn(content: String) {
  case term_supports_color() {
    True -> {
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
    False -> {
      io.println("[O_O] HEY! " <> content)
    }
  }
}

pub fn hint(content: String) {
  case term_supports_color() {
    True -> {
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
    False -> {
      io.println("[>‿0] HINT " <> content)
    }
  }
}

pub fn info(content: String) {
  case term_supports_color() {
    True -> {
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
    False -> {
      io.println("[0‿0] INFO " <> content)
    }
  }
}

pub fn start_progress(text: String) -> Option(spinner.Spinner) {
  case term_supports_color() {
    True -> {
      let spinner =
        spinner.new(text)
        |> spinner.with_colour(ansi.blue)
        |> spinner.start()
      Some(spinner)
    }
    False -> {
      io.println("Progress: " <> text)
      None
    }
  }
}

pub fn set_progress(spinner: Option(spinner.Spinner), text: String) -> Nil {
  case spinner {
    Some(spinner) -> spinner.set_text(spinner, text)
    None -> {
      io.println("Progress: " <> text)
      Nil
    }
  }
}

pub fn stop_progress(spinner: Option(spinner.Spinner)) -> Nil {
  case spinner {
    Some(spinner) -> spinner.stop(spinner)
    None -> Nil
  }
}

pub fn show_cmd(content: String) {
  case term_supports_color() {
    True -> {
      { "\n " <> ansi.dim("$") <> " " <> ansi.bold(content) <> "\n" }
      |> io.println()
    }
    False -> {
      io.println("\n $ " <> content <> "\n")
    }
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

/// (Taken from the old gleam_stlib where it was `list.pop_map`)
/// Removes the first element in a given list for which the given function returns
/// `Ok(new_value)`, then returns the wrapped `new_value` as well as list with the value removed.
///
/// Returns `Error(Nil)` if no such element is found.
///
/// ## Examples
///
/// ```gleam
/// find_map_remove([[], [2], [3]], first)
/// // -> Ok(#(2, [[], [3]]))
/// ```
///
/// ```gleam
/// find_map_remove([[], []], first)
/// // -> Error(Nil)
/// ```
///
/// ```gleam
/// find_map_remove([], first)
/// // -> Error(Nil)
/// ```
///
pub fn find_map_remove(
  in haystack: List(a),
  one_that is_desired: fn(a) -> Result(b, c),
) -> Result(#(b, List(a)), Nil) {
  find_map_remove_loop(haystack, is_desired, [])
}

fn find_map_remove_loop(
  list: List(a),
  mapper: fn(a) -> Result(b, e),
  checked: List(a),
) -> Result(#(b, List(a)), Nil) {
  case list {
    [] -> Error(Nil)
    [x, ..rest] ->
      case mapper(x) {
        Ok(y) -> Ok(#(y, list.append(list.reverse(checked), rest)))
        Error(_) -> find_map_remove_loop(rest, mapper, [x, ..checked])
      }
  }
}

/// (Taken from the old gleam_stlib where it was `list.pop`)
/// 
/// Removes the first element in a given list for which the predicate function returns `True`.
///
/// Returns `Error(Nil)` if no such element is found.
///
/// ## Examples
///
/// ```gleam
/// find_remove([1, 2, 3], fn(x) { x > 2 })
/// // -> Ok(#(3, [1, 2]))
/// ```
///
/// ```gleam
/// find_remove([1, 2, 3], fn(x) { x > 4 })
/// // -> Error(Nil)
/// ```
///
/// ```gleam
/// find_remove([], fn(_) { True })
/// // -> Error(Nil)
/// ```
///
pub fn find_remove(
  in list: List(a),
  one_that is_desired: fn(a) -> Bool,
) -> Result(#(a, List(a)), Nil) {
  find_remove_loop(list, is_desired, [])
}

fn find_remove_loop(haystack, predicate, checked) {
  case haystack {
    [] -> Error(Nil)
    [x, ..rest] ->
      case predicate(x) {
        True -> Ok(#(x, list.append(list.reverse(checked), rest)))
        False -> find_remove_loop(rest, predicate, [x, ..checked])
      }
  }
}

@external(erlang, "chrobot_ffi", "get_time_ms")
pub fn get_time_ms() -> Int
