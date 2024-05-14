//// An actor that manages an instance of the chrome browser via an erlang port.
//// The browser is started to allow remote debugging via pipes, once the pipe is disconnected,
//// chrome should quit automatically.
//// 
//// All messages to the browser are sent through this actor to the port, and responses are returned to the sender.
//// The actor manages associating responses with the correct request by adding auto-incrementing ids to the requests,
//// so callers don't need to worry about this.
//// 
//// When the browser managed by this actor is closed, the actor will also exit.
//// 
//// To start a browser, it's preferrable to use the launch functions from the root chrobot module,
//// which perform additional checks and validations.
//// 

// TODO: Port messages are not properly handeled yet
// Port messages can be **partial**, if they are not terminated with a null byte
// This is rare but can be the case for large data transfers
// we need to implement a buffer in the browser state!

import chrobot/internal/utils
import filepath as path
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
import gleam/string_builder as sb
import simplifile as file

const default_message_timeout: Int = 5000

// --- PUBLIC API ---

pub type BrowserConfig {
  BrowserConfig(path: String, args: List(String), start_timeout: Int)
}

pub type BrowserInstance {
  BrowserInstance(port: Port)
}

pub type BrowserVersion {
  BrowserVersion(
    protocol_version: String,
    product: String,
    revision: String,
    user_agent: String,
    js_version: String,
  )
}

/// Errors that may occur during launch of the browser instance
pub type LaunchError {
  UnknowOperatingSystem
  CouldNotFindExecutable
  FailedToStart
  /// This is used by the launch functions of the root `chrobot` module
  UnresponsiveAfterStart
  ProtocolVersionMismatch(
    /// Version supported by the protocol
    supported_version: String,
    /// Version the browser reported
    got_version: String,
  )
}

/// Errors that may occur when a protocol request is made
pub type RequestError {
  // Port communication failed
  PortError
  /// OTP actor timeout
  ChromeAgentTimeout

  /// OTP actor down
  ChromeAgentDown

  /// The ProtocolError variant is used by `/protocol` domains 
  /// to return a homogeneous error type for all requests.
  ProtocolError

  /// This is an error response from the browser itself
  BrowserError(code: Int, message: String, data: String)
}

/// Launch a browser with the given configuration,
/// to populate the arguments, use `get_default_chrome_args`.
/// 
/// Be aware that this function will not validate that the browser launched successfully,
/// please use the higher level functions from the root chrobot module instead if you want these guarantees.
/// 
/// ## Example
/// ```gleam
/// let config =
/// BrowserConfig(
///   path: "chrome/linux-116.0.5793.0/chrome-linux64/chrome",
///   args: get_default_chrome_args(),
///   start_timeout: 5000,
/// )
/// let assert Ok(browser_subject) = launch_with_config(config)
/// ```
pub fn launch_with_config(cfg: BrowserConfig) {
  let launch_result =
    actor.start_spec(actor.Spec(
      init: create_init_fn(cfg),
      loop: loop,
      init_timeout: cfg.start_timeout,
    ))

  case launch_result {
    Ok(browser) -> Ok(browser)
    Error(err) -> {
      io.println("Failed to start browser")
      io.debug(err)
      Error(FailedToStart)
    }
  }
}

/// Try to find a chrome installation and launch it with default arguments.
/// 
/// First, it will try to find a local chrome installation, like that created by `npx @puppeteer/browsers install chrome`
/// If that fails, it will try to find a system chrome installation in some common places.
/// 
/// For consistency it would be preferrable to not use this function and instead use `launch_with_config` with a `BrowserConfig`
/// that specifies the path to the chrome executable.
/// 
/// Be aware that this function will not validate that the browser launched successfully,
/// please use the higher level functions from the root chrobot module instead if you want these guarantees.
pub fn launch() {
  use resolved_chrome_path <- result.try(result.lazy_or(
    get_local_chrome_path(),
    get_system_chrome_path,
  ))
  launch_with_config(BrowserConfig(
    path: resolved_chrome_path,
    args: get_default_chrome_args(),
    start_timeout: 10_000,
  ))
}

/// Quit the browser and shut down the actor.  
/// This function will attempt graceful shutdown, if the browser does not respond in time,
/// it will also send a kill signal to the actor to force it to shut down.
/// The result typing reflects the success of graceful shutdown.
pub fn quit(browser: Subject(Message)) {
  // set a deadline for a kill signal to be sent if the browser does not respond in time
  let _ = process.send_after(browser, default_message_timeout * 2, Kill)
  // invoke graceful shutdown of the browser
  process.try_call(browser, Shutdown(_), default_message_timeout)
}

/// Issue a protocol call to the browser and expect a response
pub fn call(
  browser: Subject(Message),
  method: String,
  params: Option(Json),
  session_id: Option(String),
  time_out,
) -> Result(d.Dynamic, RequestError) {
  process.try_call(browser, Call(_, method, params, session_id), time_out)
  |> transform_call_response()
}

/// A blocking call that waits for a specified event to arrive once,
/// and then resolves, removing the event listener.
pub fn listen_once(browser: Subject(Message), method: String, time_out) {
  let event_subject = process.new_subject()
  let call_response =
    utils.try_call_with_subject(
      browser,
      AddListener(_, method),
      event_subject,
      time_out,
    )
  process.send(browser, RemoveListener(event_subject))
  case call_response {
    Ok(res) -> Ok(res)
    Error(process.CallTimeout) -> Error(ChromeAgentTimeout)
    Error(process.CalleeDown(_reason)) -> Error(ChromeAgentDown)
  }
}

/// Issue a protocol call to the browser without waiting for a response,
/// when the response arrives, it will be discarded.
/// It's probably best to not use this and instead just use `call` and discard unneeded responses.
/// All protocol calls yield a response and can be used with `call`, even if they
/// don't specify any response parameters.
pub fn send(
  browser: Subject(Message),
  method: String,
  params: Option(Json),
) -> Nil {
  process.send(browser, Send(method, params))
}

/// Hardcoded protocol call to get the browser version
/// See: https://chromedevtools.github.io/devtools-protocol/tot/Browser/#method-getVersion 
pub fn get_version(
  browser: Subject(Message),
) -> Result(BrowserVersion, RequestError) {
  use res <- result.try(call(
    browser,
    "Browser.getVersion",
    None,
    None,
    default_message_timeout,
  ))
  let version_decoder =
    d.decode5(
      BrowserVersion,
      d.field("protocolVersion", d.string),
      d.field("product", d.string),
      d.field("revision", d.string),
      d.field("userAgent", d.string),
      d.field("jsVersion", d.string),
    )
  case version_decoder(res) {
    Ok(version) -> Ok(version)
    Error(_) -> Error(ProtocolError)
  }
}

/// Get the default arguments the browser should be started with,
/// to be used inside the `launch_with_config` function
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

/// Returns whether the given path is a local chrome installation, of the kind
/// created by `npx @puppeteer/browsers install chrome`.
/// This can be used to scan a directory with `simplifile.get_files`.
pub fn is_local_chrome_path(
  relative_path: String,
  os_family: os.OsFamily,
) -> Bool {
  case os_family, path.split(relative_path) {
    os.Darwin,
      [
        "chrome",
        "mac" <> _,
        "chrome-" <> _,
        "Google Chrom" <> _,
        "Contents",
        "MacOS",
        "Google Chrom" <> _,
      ]
    -> {
      True
    }
    os.Linux, ["chrome", "linux" <> _, "chrome-" <> _, "chrome"] -> {
      True
    }
    // No idea if this works, I don't have a windows computer to test
    os.WindowsNt, ["chrome", "win" <> _, "chrome-" <> _, "chrome.exe"] -> {
      True
    }
    _, _ -> False
  }
}

/// Try to find a hermetic chrome installation in the current directory,
/// of the kind installed by `npx @puppeteer/browsers install chrome`.
/// The installation must be in a directory called `chrome`.
pub fn get_local_chrome_path() {
  case file.verify_is_directory("chrome") {
    Ok(True) -> {
      let files_res =
        result.replace_error(file.get_files("chrome"), CouldNotFindExecutable)
      use files <- result.try(files_res)
      list.find(files, fn(file) { is_local_chrome_path(file, os.family()) })
      |> result.replace_error(CouldNotFindExecutable)
    }
    _ -> {
      Error(CouldNotFindExecutable)
    }
  }
}

/// Try to find a system chrome installation in some obvious places.
pub fn get_system_chrome_path() {
  case os.family() {
    os.Darwin ->
      get_first_existing_path([
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta",
        "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary",
        "/Applications/Google Chrome Dev.app/Contents/MacOS/Google Chrome Dev",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
      ])
    os.Linux ->
      get_first_existing_path([
        "/opt/google/chrome/chrome", "/opt/google/chrome-beta/chrome",
        "/opt/google/chrome-unstable/chrome", "/usr/bin/chromium",
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

// --- INITIALIZATION ---

/// Returns a function that can be passed to the actor spec to initialize the actor
fn create_init_fn(cfg: BrowserConfig) {
  fn() {
    io.println("Starting browser exectuable: " <> cfg.path)
    let cmd = cfg.path
    let args = ["--remote-debugging-pipe", ..cfg.args]
    // io.println(cmd <> " " <> string.join(args, " "))
    let res = open_browser_port(cmd, args)
    case res {
      Ok(port) -> {
        let instance = BrowserInstance(port)
        log(instance, "Started")
        actor.Ready(
          BrowserState(instance, 0, [], [], sb.new(), None),
          process.new_selector()
            |> process.selecting_record2(port, map_port_message),
        )
      }
      Error(err) -> {
        io.debug(#("Browser start error: ", string.inspect(err)))
        actor.Failed("Browser did not start")
      }
    }
  }
}

// --- MESSAGE HANDLING ---

/// Map a raw message from the port to a message that the actor can handle
fn map_port_message(message: d.Dynamic) -> Message {
  // This matches a data message from the port like {data, "string"}
  // not ideal but actually should be fine since data messages are the only messages 
  // from the port that will arrive as a tuple with a string as the second element,
  // and these are the main messages we are interested in and want to handle quickly.
  //
  // other messages will be atoms (closed/connected) and {exit_code, int}
  // which are handled by the fallback map function below
  case d.element(1, d.string)(message) {
    Ok(data) -> PortResponse(data)
    Error(_) -> map_non_data_port_msg(message)
  }
}

/// Handle a message from the port that is not a data message.
/// Right now we are handling exit_code messages, which tell us that the port 
/// has exited or failed to properly start.
fn map_non_data_port_msg(msg: d.Dynamic) -> Message {
  let decoded_msg = d.tuple2(atom.from_dynamic, d.int)(msg)
  case decoded_msg {
    Ok(#(atom_exit_status, exit_status)) -> {
      case atom_exit_status == atom.create_from_string("exit_status") {
        True -> PortExit(exit_status)
        False -> UnexpectedPortMessage(msg)
      }
    }
    Error(_) -> UnexpectedPortMessage(msg)
  }
}

/// Processes an input string and returns a list of complete packets
/// as well as the updated buffer containing overflow data
@internal
pub fn process_port_message(input: String, chunks: List(String), buffer: sb.StringBuilder) -> #(
  List(String),
  sb.StringBuilder,
) {
  case string.pop_grapheme(input) {
    Ok(#("\u{0000}", rest)) -> {
      // Null byte reached -> the buffer is a complete package, but there is more!
      process_port_message(rest, [sb.to_string(buffer), ..chunks], sb.new())
    }
    Ok(#(current, rest)) -> {
      process_port_message(rest, chunks, sb.append(buffer, current))
    }
    Error(Nil) -> #(list.reverse(chunks), buffer)
  }
}

type BrowserState {
  BrowserState(
    instance: BrowserInstance,
    next_id: Int,
    unanswered_requests: List(PendingRequest),
    event_listeners: List(#(String, Subject(d.Dynamic))),
    message_buffer: sb.StringBuilder,
    shutdown_request: Option(Subject(Nil)),
  )
}

pub type Message {
  /// Initiate graceful shutdown of the browser
  Shutdown(reply_with: Subject(Nil))
  /// Kill by shutting down actor
  Kill
  /// Make a protocol call and receive response
  Call(
    reply_with: Subject(Result(d.Dynamic, RequestError)),
    method: String,
    params: Option(Json),
    session_id: Option(String),
  )
  /// Make a protocol call and ignore response
  Send(method: String, params: Option(Json))
  // Add an event listener
  AddListener(listener: Subject(d.Dynamic), method: String)
  // Remove an event listener
  RemoveListener(listener: Subject(d.Dynamic))
  /// (From Port) Message that could not be matched
  UnexpectedPortMessage(d.Dynamic)
  /// (From Port) Protocol Message
  PortResponse(String)
  /// (From Port) Port has exited
  PortExit(Int)
}

type PendingRequest {
  PendingRequest(id: Int, reply_with: Subject(Result(d.Dynamic, RequestError)))
}

/// The main loop of the actor, handling all messages
fn loop(message: Message, state: BrowserState) {
  case message {
    Kill -> {
      log(
        state.instance,
        "Received kill signal, actor is shutting down, this is unuasual and means the browser did not respond to a shutdown request in time!",
      )
      actor.Stop(process.Normal)
    }
    Call(client, method, params, session_id) -> {
      // Handle call leaves the calling process hanging until a response is received
      // from the browser, which must be sent back to the client
      handle_call(state, client, method, params, session_id)
    }
    Send(method, params) -> {
      handle_send(state, method, params)
    }
    AddListener(client, method) -> {
      let updated_listeners = [#(method, client), ..state.event_listeners]
      log(
        state.instance,
        "Event listeners: " <> string.inspect(updated_listeners),
      )
      actor.continue(BrowserState(
        instance: state.instance,
        next_id: state.next_id,
        unanswered_requests: state.unanswered_requests,
        event_listeners: updated_listeners,
        message_buffer: state.message_buffer,
        shutdown_request: state.shutdown_request,
      ))
    }
    RemoveListener(client) -> {
      let updated_listeners =
        list.filter(state.event_listeners, fn(l) { l.1 != client })
      log(
        state.instance,
        "Event listeners: " <> string.inspect(updated_listeners),
      )
      actor.continue(BrowserState(
        instance: state.instance,
        next_id: state.next_id,
        unanswered_requests: state.unanswered_requests,
        event_listeners: updated_listeners,
        message_buffer: state.message_buffer,
        shutdown_request: state.shutdown_request,
      ))
    }
    PortResponse(data) -> {
      let #(chunks, buffer) =
        process_port_message(data, [], state.message_buffer)

      let updated_state =
        chunks
        |> list.fold(state, fn(acc, curr) { handle_port_response(acc, curr) })

      actor.continue(BrowserState(
        instance: updated_state.instance,
        next_id: updated_state.next_id,
        unanswered_requests: updated_state.unanswered_requests,
        event_listeners: updated_state.event_listeners,
        message_buffer: buffer,
        shutdown_request: updated_state.shutdown_request,
      ))
    }
    UnexpectedPortMessage(msg) -> {
      log(
        state.instance,
        "Got an unexpected message from the port! This should not happen!",
      )
      io.debug(msg)
      actor.continue(state)
    }
    Shutdown(client) -> {
      // Initiate shutdown of the browser
      // the process is left hanging and should be replied to when the browser
      // has successfully shut down -> PortExit message below
      log(
        state.instance,
        "Received shutdown request, attempting to quit browser",
      )
      handle_send(state, "Browser.close", None)
      actor.continue(BrowserState(
        instance: state.instance,
        next_id: state.next_id,
        unanswered_requests: state.unanswered_requests,
        event_listeners: state.event_listeners,
        message_buffer: state.message_buffer,
        shutdown_request: Some(client),
      ))
    }
    PortExit(exit_status) -> {
      // The browser has exited
      case state.shutdown_request {
        Some(client) -> {
          log(
            state.instance,
            "Browser exited after shtudown request, actor is shutting down",
          )
          process.send(client, Nil)
          actor.Stop(process.Normal)
        }
        _ -> {
          log(
            state.instance,
            "Browser exited but there was no shutdown request! Exit Status: "
              <> string.inspect(exit_status)
              <> " browser actor is shutting down abnormally",
          )
          actor.Stop(process.Abnormal(reason: "browser exited abnormally"))
        }
      }
    }
  }
}

/// Send a request to the browser and expect a response
/// Request params must already be encoded into a JSON structure by the caller
/// The response will be sent back to the client subject when it arrives from the browser
fn handle_call(
  state: BrowserState,
  client: Subject(Result(d.Dynamic, RequestError)),
  method: String,
  params: Option(Json),
  session_id: Option(String),
) {
  let request_id = state.next_id
  let request_memo = PendingRequest(id: request_id, reply_with: client)
  let payload =
    json.object(
      [#("id", json.int(request_id)), #("method", json.string(method))]
      |> utils.add_optional(params, fn(some_params) { #("params", some_params) })
      |> utils.add_optional(session_id, fn(some_session_id) {
        #("sessionId", json.string(some_session_id))
      }),
    )

  case send_to_browser(state.instance, payload) {
    Error(_) -> {
      log(state.instance, "Request call to browser was unsuccessful!")
      process.send(client, Error(PortError))
      actor.continue(BrowserState(
        instance: state.instance,
        next_id: request_id + 1,
        unanswered_requests: state.unanswered_requests,
        event_listeners: state.event_listeners,
        message_buffer: state.message_buffer,
        shutdown_request: state.shutdown_request,
      ))
    }
    Ok(_) -> {
      actor.continue(BrowserState(
        instance: state.instance,
        next_id: request_id + 1,
        unanswered_requests: [request_memo, ..state.unanswered_requests],
        event_listeners: state.event_listeners,
        message_buffer: state.message_buffer,
        shutdown_request: state.shutdown_request,
      ))
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
      |> utils.add_optional(params, fn(some_params) { #("params", some_params) }),
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
    event_listeners: state.event_listeners,
    message_buffer: state.message_buffer,
    shutdown_request: state.shutdown_request,
  ))
}

/// Find the pending request in the state and send the response data to the client.
/// Failure to find the associated request will silently discard the response
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
      // Silently discard the response if there is no request to match it
      // this happens if clients use send instead of call, which does not create
      // a pending request
      state.unanswered_requests
    }
  }
}

/// Find the pending request in the state and send the error data to the client.
/// Failure to find the associated request will log an error
fn answer_failed_request(
  state: BrowserState,
  id: Int,
  data: RawBrowserError,
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
      process.send(
        req.reply_with,
        Error(BrowserError(
          option.unwrap(data.code, 0),
          option.unwrap(data.message, "No message"),
          option.unwrap(data.data, "No data"),
        )),
      )
      rest
    }
    Error(Nil) -> {
      log(
        state.instance,
        "An error arrived from the browser but could not be associated with a request: "
          <> string.inspect(data),
      )
      state.unanswered_requests
    }
  }
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
    error: Option(RawBrowserError),
  )
}

type RawBrowserError {
  RawBrowserError(
    code: Option(Int),
    message: Option(String),
    data: Option(String),
  )
}

/// Handle a message from the browser, delivered via the port.
/// The message can be a response to a request or an event
fn handle_port_response(state: BrowserState, response: String) -> BrowserState {
  let error_decoder =
    d.decode3(
      RawBrowserError,
      d.optional_field("code", d.int),
      d.optional_field("message", d.string),
      d.optional_field("data", d.string),
    )
  // The decoder contains all possible fields of the response, event or request response
  let response_decoder =
    d.decode5(
      BrowserResponse,
      d.optional_field("id", d.int),
      d.optional_field("result", d.dynamic),
      d.optional_field("method", d.string),
      d.optional_field("params", d.dynamic),
      d.optional_field("error", error_decoder),
    )
  case json.decode(response, response_decoder) {
    Ok(BrowserResponse(Some(id), Some(result), None, None, None)) -> {
      // A response to a request -> should be sent to the client
      BrowserState(
        instance: state.instance,
        next_id: state.next_id,
        unanswered_requests: answer_request(state, id, result),
        event_listeners: state.event_listeners,
        message_buffer: state.message_buffer,
        shutdown_request: state.shutdown_request,
      )
    }
    Ok(BrowserResponse(Some(id), _, _, _, Some(raw_error))) -> {
      // A response to a request that resulted in an error
      BrowserState(
        instance: state.instance,
        next_id: state.next_id,
        unanswered_requests: answer_failed_request(state, id, raw_error),
        event_listeners: state.event_listeners,
        message_buffer: state.message_buffer,
        shutdown_request: state.shutdown_request,
      )
    }
    Ok(BrowserResponse(None, None, Some(method), Some(params), None)) -> {
      // An event from the browser
      // -> forward to any listeners
      list.each(state.event_listeners, fn(l) {
        case l.0 == method {
          True -> process.send(l.1, params)
          False -> {
            // An event without a listener is dropped
            log(state.instance, "Ignored Event: " <> string.inspect(params))
            Nil
          }
        }
      })
      state
    }
    Ok(_) -> {
      log(
        state.instance,
        "Received an unexpectedly formatted response from the browser",
      )
      io.debug(response)
      state
    }
    Error(e) -> {
      log(state.instance, "Failed to decode data from port message, ignoring!")
      io.debug(response)
      io.debug(e)
      state
    }
  }
}

// --- HELPERS ---

/// Send a JSON encoded string to the browser instance,
/// the JSON payload must already include the `id` field.
/// This function appends a null byte to the end of the message,
/// which is used by the browser to detect when a message ends.
fn send_to_browser(instance: BrowserInstance, data: Json) {
  io.debug(json.to_string(data))
  send_to_port(instance.port, json.to_string(data) <> "\u{0000}")
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

fn log(instance: BrowserInstance, message: String) {
  io.println(string.inspect(instance) <> ": " <> message)
}

fn transform_call_response(call_response) {
  case call_response {
    Error(process.CalleeDown(_reason)) -> Error(ChromeAgentDown)
    Error(process.CallTimeout) -> Error(ChromeAgentTimeout)
    Ok(nested_result) -> nested_result
  }
}

// --- EXTERNALS ---
// Gleam does not support working with ports directly yet so we need to use FFI

@external(erlang, "chrobot_ffi", "open_browser_port")
fn open_browser_port(
  command: String,
  args: List(String),
) -> Result(Port, d.Dynamic)

@external(erlang, "chrobot_ffi", "send_to_port")
fn send_to_port(port: Port, message: String) -> Result(d.Dynamic, d.Dynamic)
