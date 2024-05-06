//// An actor that manages an instance of the chrome browser via an erlang port.
//// The browser is started to allow remote debugging via pipes, once the pipe is disconnected,
//// chrome should quite automatically.
//// 
//// All messages to the browser are sent through this actor to the port, and responses are returned to the sender.
//// The actor manages associating responses with the correct request by adding auto-incrementing ids to the requests,
//// so callers don't need to worry about this.
//// 

import gleam/dynamic as d
import gleam/erlang/atom
import gleam/erlang/os
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/port.{type Port}
import gleam/result
import gleam/string
import simplifile as file

const message_timeout: Int = 5000

pub type LaunchError {
  UnknowOperatingSystem
  CouldNotFindExecutable
  FailedToStart
}

pub type BrowserConfig {
  BrowserConfig(path: String, args: List(String), start_timeout: Int)
}

pub type BrowserInstance {
  BrowserInstance(port: Port)
}

type PendingRequest {
  PendingRequest(id: Int, reply_with: Subject(Result(d.Dynamic, Nil)))
}

type BrowserState {
  BrowserState(
    instance: BrowserInstance,
    next_id: Int,
    unanswered_requests: List(PendingRequest),
  )
}

pub fn launch_with_config(cfg: BrowserConfig) {
  let launch_result =
    actor.start_spec(actor.Spec(
      init: create_init_fn(cfg),
      loop: loop,
      init_timeout: cfg.start_timeout,
    ))

  case launch_result {
    Ok(browser) -> {
      io.debug(get_version(browser))
      Ok(browser)
    }
    Error(err) -> {
      io.println("Failed to start browser")
      io.debug(err)
      Error(FailedToStart)
    }
  }
}

pub fn launch() {
  use chrome_path <- result.try(get_default_chrome_path())
  io.println("Resolved chrome path: " <> chrome_path)

  launch_with_config(BrowserConfig(
    path: chrome_path,
    args: get_default_chrome_args(),
    start_timeout: 10_000,
  ))
}

fn log(instance: BrowserInstance, message: String) {
  io.println("[Browser:" <> string.inspect(instance) <> "] " <> message)
}

/// Get the default arguments the browser should be started with
pub fn get_default_chrome_args() {
  [
    "--headless", "--disable-accelerated-2d-canvas", "--disable-gpu",
    "--allow-pre-commit-input", "--disable-background-networking",
    "--disable-background-timer-throttling",
    "--disable-backgrounding-occluded-windows", "--disable-breakpad",
    "--disable-client-side-phishing-detection",
    "--disable-component-extensions-with-background-pages",
    "--disable-component-update", "--disable-default-apps",
    "--disable-extensions",
    "--disable-features=Translate,BackForwardCache,AcceptCHFrame,MediaRouter,OptimizationHints",
    "--disable-hang-monitor", "--disable-ipc-flooding-protection",
    "--disable-popup-blocking", "--disable-prompt-on-repost",
    "--disable-renderer-backgrounding", "--disable-sync", "--enable-automation",
    "--enable-features=NetworkServiceInProcess2", "--export-tagged-pdf",
    "--force-color-profile=srgb", "--hide-scrollbars",
    "--metrics-recording-only", "--no-default-browser-check", "--no-first-run",
    "--no-service-autorun", "--password-store=basic", "--use-mock-keychain",
  ]
}

fn get_first_existing_path(paths: List(String)) -> Result(String, LaunchError) {
  let existing_paths =
    paths
    |> list.filter(fn(current) {
      case file.verify_is_file(current) {
        Ok(res) -> res
        Error(_) -> False
      }
    })

  case existing_paths {
    [first, ..] -> Ok(first)
    [] -> Error(CouldNotFindExecutable)
  }
}

/// Try to find a chrome executable in some obvious places
/// (It should be preferred to set the path explicitly if possible)
fn get_default_chrome_path() {
  case os.family() {
    os.Darwin ->
      get_first_existing_path([
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary",
      ])
    os.Linux ->
      get_first_existing_path([
        "/usr/bin/google-chrome", "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
      ])
    os.WindowsNt ->
      get_first_existing_path([
        "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
        "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
        "C:\\Program Files\\Chromium\\Application\\chrome.exe",
        "C:\\Program Files (x86)\\Chromium\\Application\\chrome.exe",
      ])
    _ -> Error(UnknowOperatingSystem)
  }
}

pub type Message {
  Stop
  BrowserDown
  Call(
    reply_with: Subject(Result(d.Dynamic, Nil)),
    method: String,
    params: Option(Json),
  )
  Send(method: String, params: Option(Json))
  Anything(d.Dynamic)
  PortResponse(String)
}

fn create_init_fn(cfg: BrowserConfig) {
  fn() {
    io.println("Starting browser with path: " <> cfg.path)
    let cmd = cfg.path
    let args = ["--remote-debugging-pipe", ..cfg.args]
    // io.println(cmd <> " " <> string.join(args, " "))
    let res = open_browser_port(cmd, args)
    case res {
      Ok(port) -> {
        let instance = BrowserInstance(port)
        log(instance, "Started")
        actor.Ready(
          BrowserState(instance, 0, []),
          process.new_selector()
            |> process.selecting_record2(port, map_port_message)
            |> process.selecting_anything(fn(anything) { Anything(anything) }),
        )
      }
      Error(err) -> {
        io.debug(#("Browser start error: ", string.inspect(err)))
        actor.Failed("Browser did not start")
      }
    }
  }
}

type IntermediatePortMessage {
  IntermediatePortMessage(head: atom.Atom, body: String)
}

fn map_port_message(message: d.Dynamic) {
  // This matches a data message from the port
  // not ideal but actually should be fine since data messages are the only messages 
  // from the port that will arrive as a tuple with a string as the second element
  // other messages will be atoms (closed/connected)
  case d.element(1, d.string)(message) {
    Ok(data) -> PortResponse(data)
    Error(_) -> Anything(message)
  }
}

fn loop(message: Message, state: BrowserState) {
  case message {
    Stop -> {
      log(state.instance, "Stopping on request")
      todo
      actor.Stop(process.Normal)
    }
    BrowserDown -> {
      log(state.instance, "Stopping because browser exited")
      actor.Stop(process.Normal)
    }
    Call(client, method, params) -> {
      handle_call(state, client, method, params)
    }
    Send(method, params) -> {
      handle_send(state, method, params)
    }
    PortResponse(data) -> {
      handle_port_response(state, data)
    }
    Anything(msg) -> {
      log(state.instance, "Got an unexpected message")
      io.debug(msg)
      actor.continue(state)
    }
  }
}

@external(erlang, "chrobot_ffi", "open_browser_port")
fn open_browser_port(
  command: String,
  args: List(String),
) -> Result(Port, d.Dynamic)

@external(erlang, "chrobot_ffi", "send_to_port")
fn send_to_port(port: Port, message: String) -> Result(d.Dynamic, d.Dynamic)

/// Send a request to the browser and expect a response
/// Request params must already be encoded into a JSON structure by the caller
/// The response will be sent back to the client subject when it arrives from the browser
fn handle_call(
  state: BrowserState,
  client: Subject(Result(d.Dynamic, Nil)),
  method: String,
  params: Option(Json),
) {
  let request_id = state.next_id
  let request_memo = PendingRequest(id: request_id, reply_with: client)
  let payload =
    json.object(
      [#("id", json.int(request_id)), #("method", json.string(method))]
      |> add_optional_params(params),
    )
  case send_to_browser(state.instance, payload) {
    Error(_) -> {
      log(state.instance, "Request call to browser was unsuccessful!")
      io.debug(#(client, payload))
      actor.continue(BrowserState(
        instance: state.instance,
        next_id: request_id + 1,
        unanswered_requests: state.unanswered_requests,
      ))
    }
    Ok(_) -> {
      actor.continue(
        BrowserState(
          instance: state.instance,
          next_id: request_id + 1,
          unanswered_requests: [request_memo, ..state.unanswered_requests],
        ),
      )
    }
  }
}

/// Send a request that does not expect a response
/// Request params must already be encoded into a JSON structure by the caller
fn handle_send(state: BrowserState, method: String, params: Option(Json)) {
  let request_id = state.next_id
  let payload =
    json.object(
      [#("id", json.int(request_id)), #("method", json.string(method))]
      |> add_optional_params(params),
    )
  case send_to_browser(state.instance, payload) {
    Error(_) -> {
      log(state.instance, "Request sent to browser was unsuccessful!")
      io.debug(payload)
      Nil
    }
    Ok(_) -> {
      Nil
    }
  }
  actor.continue(BrowserState(
    instance: state.instance,
    next_id: request_id + 1,
    unanswered_requests: state.unanswered_requests,
  ))
}

// Browser response can either be a response to a request or an event
// Response to a request has an 'id' and a 'result' field
// Event has a 'method' and 'params' field
type BrowserResponse {
  BrowserResponse(
    id: Option(Int),
    result: Option(d.Dynamic),
    method: Option(String),
    params: Option(d.Dynamic),
  )
}

/// Find the pending request in the state and send the response data to the client
/// Failure to find the associated request will log an error and ignore the response
fn answer_request(
  state: BrowserState,
  id: Int,
  data: d.Dynamic,
) -> List(PendingRequest) {
  // Request is selected from the list and removed based on id
  let found_request =
    list.pop_map(state.unanswered_requests, fn(req) {
      case req.id == id {
        True -> Ok(req)
        False -> Error(Nil)
      }
    })
  case found_request {
    Ok(#(req, rest)) -> {
      process.send(req.reply_with, Ok(data))
      rest
    }
    Error(Nil) -> {
      log(
        state.instance,
        "Received a response for an unknown request, id:" <> string.inspect(id),
      )
      io.debug(data)
      state.unanswered_requests
    }
  }
}

/// Handele a message from the browser, delivered via the port
/// The message can be a response to a request or an event
fn handle_port_response(
  state: BrowserState,
  raw_response: String,
) -> actor.Next(a, BrowserState) {
  // The response is expected to be a JSON string, with a null byte at the end
  // we need to remove the null byte before decoding
  let response = string.drop_right(raw_response, 1)
  // The decoder contains all possible fields of the response, event or request response
  let response_decoder =
    d.decode4(
      BrowserResponse,
      d.optional_field("id", d.int),
      d.optional_field("result", d.dynamic),
      d.optional_field("method", d.string),
      d.optional_field("params", d.dynamic),
    )
  case json.decode(response, response_decoder) {
    Ok(BrowserResponse(Some(id), Some(result), None, None)) -> {
      // A response to a request -> should be sent to the client
      actor.continue(BrowserState(
        instance: state.instance,
        next_id: state.next_id,
        unanswered_requests: answer_request(state, id, result),
      ))
    }
    Ok(BrowserResponse(None, None, Some(method), Some(params))) -> {
      // TODO An event from the browser
      log(
        state.instance,
        "Received an event, event forwarding is not implemented yet",
      )
      io.debug(#(method, params))
      actor.continue(state)
    }
    Ok(_) -> {
      log(
        state.instance,
        "Received an unexpectedly formatted response from the browser",
      )
      io.debug(response)
      actor.continue(state)
    }
    Error(e) -> {
      log(state.instance, "Failed to decode data from port message, ignoring!")
      io.debug(response)
      io.debug(e)
      actor.continue(state)
    }
  }
}

fn add_optional_params(payload: List(#(String, Json)), params: Option(Json)) {
  case params {
    option.Some(data) -> [#("params", data), ..payload]
    option.None -> payload
  }
}

/// Send a JSON encoded string to the browser instance
/// The JSON payload must include an `id` field
fn send_to_browser(instance: BrowserInstance, data: Json) {
  send_to_port(instance.port, json.to_string(data) <> "\u{0000}")
}

// fn request_version(port: Port) {
//   send_to_port(port, "{\"id\":1,\"method\":\"Browser.getVersion\"}\u{0000}")
// }

pub fn get_version(browser: Subject(Message)) {
  actor.call(
    browser,
    Call(_, "Browser.getVersion", option.None),
    message_timeout,
  )
}
