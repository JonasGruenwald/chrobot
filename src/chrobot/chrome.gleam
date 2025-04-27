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

import chrobot/internal/utils
import envoy
import filepath as path
import gleam/dynamic as d
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/os
import gleam/erlang/port.{type Port}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/string_tree as st
import simplifile as file

pub const default_timeout: Int = 10_000

// --- PUBLIC API ---

/// The log level the browser is using.  
pub type LogLevel {
  /// Log nothing
  LogLevelSilent
  /// Log only warnings, this is the default
  LogLevelWarnings
  /// Log normal but uncommon events, like buffering a long message, shutdown
  LogLevelInfo
  /// Log everything, including protocol payloads
  LogLevelDebug
}

pub type BrowserConfig {
  BrowserConfig(
    path: String,
    args: List(String),
    start_timeout: Int,
    log_level: LogLevel,
  )
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

  /// A requested resource could not be found
  NotFoundError

  /// A runtime exception thrown by JavaScript code being evaluated in the browser
  RuntimeException(text: String, line: Int, column: Int)
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
pub fn launch_with_config(
  cfg: BrowserConfig,
) -> Result(Subject(Message), LaunchError) {
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
      io.println(string.inspect(err))
      Error(FailedToStart)
    }
  }
}

/// Cleverly try to find a chrome installation and launch it with reasonable defaults.
/// 
/// 1. If `CHROBOT_BROWSER_PATH` is set, use that
/// 2. If a local chrome installation is found, use that
/// 3. If a system chrome installation is found, use that
/// 4. If none of the above, return an error
/// 
/// If you want to always use a specific chrome installation, take a look at `launch_with_config` or 
/// `launch_with_env` to set the path explicitly.
///  
/// Be aware that this function will not validate that the browser launched successfully,
/// please use the higher level functions from the root chrobot module instead if you want these guarantees.
pub fn launch() -> Result(Subject(Message), LaunchError) {
  case resolve_env_cofig() {
    Ok(env_config) -> {
      // Env config vars are set, use them
      utils.info(
        "Launching browser using config provided through environment variables",
      )
      launch_with_config(env_config)
    }
    Error(_) -> {
      // Try local first, then a system installation
      use resolved_chrome_path <- result.try(result.lazy_or(
        get_local_chrome_path(),
        get_system_chrome_path,
      ))
      // I think logging this is important to avoid confusion
      utils.info(
        "Launching browser from dynamically resolved path: \""
        <> resolved_chrome_path
        <> "\"",
      )
      launch_with_config(BrowserConfig(
        path: resolved_chrome_path,
        args: get_default_chrome_args(),
        start_timeout: default_timeout,
        log_level: LogLevelWarnings,
      ))
    }
  }
}

/// Like [`launch`](#launch), but launches the browser with a visible window, not
/// in headless mode, which is useful for debugging and development.  
pub fn launch_window() -> Result(Subject(Message), LaunchError) {
  case resolve_env_cofig() {
    Ok(env_config) -> {
      // Env config vars are set, use them
      utils.info(
        "Launching windowed browser using config provided through environment variables",
      )
      launch_with_config(BrowserConfig(
        path: env_config.path,
        args: env_config.args
          |> list.filter(fn(arg) {
            case arg {
              "--headless" -> False
              _ -> True
            }
          }),
        start_timeout: env_config.start_timeout,
        log_level: env_config.log_level,
      ))
    }
    Error(_) -> {
      // Try local first, then a system installation
      use resolved_chrome_path <- result.try(result.lazy_or(
        get_local_chrome_path(),
        get_system_chrome_path,
      ))
      // I think logging this is important to avoid confusion
      utils.info(
        "Launching windowed browser from dynamically resolved path: \""
        <> resolved_chrome_path
        <> "\"",
      )
      launch_with_config(BrowserConfig(
        path: resolved_chrome_path,
        args: get_default_chrome_args()
          |> list.filter(fn(arg) {
            case arg {
              "--headless" -> False
              _ -> True
            }
          }),
        start_timeout: default_timeout,
        log_level: LogLevelWarnings,
      ))
    }
  }
}

/// Launch a browser, and read the configuration from environment variables.
/// The browser path variable must be set, all others will fall back to a default.
/// 
/// Be aware that this function will not validate that the browser launched successfully,
/// please use the higher level functions from the root chrobot module instead if you want these guarantees.
/// 
/// Configuration variables:
/// - `CHROBOT_BROWSER_PATH` - The path to the browser executable
/// - `CHROBOT_BROWSER_ARGS` - The arguments to pass to the browser, separated by spaces
/// - `CHROBOT_BROWSER_TIMEOUT` - The timeout in milliseconds to wait for the browser to start, must be an integer
/// - `CHROBOT_LOG_LEVEL` - The log level to use, one of `silent`, `warnings`, `info`, `debug`
pub fn launch_with_env() -> Result(Subject(Message), LaunchError) {
  case resolve_env_cofig() {
    Ok(env_config) -> launch_with_config(env_config)
    Error(_) -> {
      utils.err(
        "Failed to resolve browser configuration from environment variables, please check that they are set correctly",
      )
      Error(CouldNotFindExecutable)
    }
  }
}

/// Quit the browser and shut down the actor.  
/// This function will attempt graceful shutdown, if the browser does not respond in time,
/// it will also send a kill signal to the actor to force it to shut down.
/// The result typing reflects the success of graceful shutdown.
pub fn quit(browser: Subject(Message)) {
  // set a deadline for a kill signal to be sent if the browser does not respond in time
  let _ = process.send_after(browser, default_timeout * 2, Kill)
  // invoke graceful shutdown of the browser
  process.try_call(browser, Shutdown, default_timeout)
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
pub fn listen_once(
  browser: Subject(Message),
  method: String,
  time_out,
) -> Result(d.Dynamic, RequestError) {
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

/// Add an event listener
/// (Experimental! Event forwarding is not really supported yet)
pub fn add_listener(browser, method: String) -> Subject(d.Dynamic) {
  let event_subject = process.new_subject()
  process.send(browser, AddListener(event_subject, method))
  event_subject
}

/// Remove an event listener
/// (Experimental! Event forwarding is not really supported yet)
pub fn remove_listener(browser, listener: Subject(d.Dynamic)) -> Nil {
  process.send(browser, RemoveListener(listener))
}

/// Allows you to set the log level of a running browser instance
pub fn set_log_level(browser, level: LogLevel) -> Nil {
  process.send(browser, SetLogLevel(level))
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
    default_timeout,
  ))
  let version_decoder = {
    use protocol_version <- decode.field("protocolVersion", decode.string)
    use product <- decode.field("product", decode.string)
    use revision <- decode.field("revision", decode.string)
    use user_agent <- decode.field("userAgent", decode.string)
    use js_version <- decode.field("jsVersion", decode.string)
    decode.success(BrowserVersion(
      protocol_version:,
      product:,
      revision:,
      user_agent:,
      js_version:,
    ))
  }
  case decode.run(res, version_decoder) {
    Ok(version) -> Ok(version)
    Error(_) -> Error(ProtocolError)
  }
}

/// Get the default arguments the browser should be started with,
/// to be used inside the `launch_with_config` function
pub fn get_default_chrome_args() -> List(String) {
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
/// created by `browser_install` or the puppeteer install script.
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
/// of the kind installed by `browser_install` or the puppeteer install script.
/// The installation must be in a directory called `chrome`.
pub fn get_local_chrome_path() {
  get_local_chrome_path_at("chrome")
}

@internal
pub fn get_local_chrome_path_at(base_dir: String) {
  case file.is_directory(base_dir) {
    Ok(True) -> {
      let files_res =
        result.replace_error(file.get_files(base_dir), CouldNotFindExecutable)
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
    let cmd = cfg.path
    let args = ["--remote-debugging-pipe", ..cfg.args]
    let res = open_browser_port(cmd, args)
    case res {
      Ok(port) -> {
        let instance = BrowserInstance(port)
        let initial_state =
          BrowserState(instance, 0, [], [], st.new(), None, cfg.log_level)
        log_info(initial_state, "Port opened successfully, actor initialized")
        actor.Ready(
          initial_state,
          process.new_selector()
            |> process.selecting_record2(port, map_port_message),
        )
      }
      Error(err) -> {
        utils.err("Browser failed to start!")
        io.println(string.inspect(err))
        actor.Failed("Browser did not start")
      }
    }
  }
}

// --- MESSAGE HANDLING ---

type RawPortMessage {
  RawPortMessageData(String)
  RawPortMessageExit(Int)
  RawPortMessageUnexpected(d.Dynamic)
}

/// Map a raw message from the port to a message that the actor can handle
fn map_port_message(message: d.Dynamic) -> Message {
  let data_decoder = {
    use message <- decode.field(1, decode.string)
    decode.success(RawPortMessageData(message))
  }

  let exit_decoder = {
    use exit_status <- decode.field(1, decode.int)
    decode.success(RawPortMessageExit(exit_status))
  }

  let unexpected_decoder = {
    use data <- decode.then(decode.dynamic)
    decode.success(RawPortMessageUnexpected(data))
  }

  let decoder = {
    let atom_data = atom.create_from_string("data")
    let atom_exit_status = atom.create_from_string("exit_status")
    use atom_tag <- decode.field(0, decode.dynamic)
    case atom.from_dynamic(atom_tag) {
      Ok(tag) if tag == atom_data -> data_decoder
      Ok(tag) if tag == atom_exit_status -> exit_decoder
      Ok(_) | Error(_) -> unexpected_decoder
    }
  }
  case decode.run(message, decoder) {
    Ok(RawPortMessageData(data)) -> PortResponse(data)
    Ok(RawPortMessageExit(exit_status)) -> PortExit(exit_status)
    Ok(RawPortMessageUnexpected(other)) -> UnexpectedPortMessage(other)
    Error(_) -> UnexpectedPortMessage(message)
  }
}

/// Processes an input string and returns a list of complete packets
/// as well as the updated buffer containing overflow data
@internal
pub fn process_port_message(
  input: String,
  buffer: st.StringTree,
) -> #(List(String), st.StringTree) {
  case string.split(input, "\u{0000}") {
    [unterminated_msg] -> #([], st.append(buffer, unterminated_msg))
    // Match on this case directly even though it would be handled by the next case
    // because it is the most common case and we want to avoid the overhead of the list recursion
    [single_msg, ""] -> #(
      [st.append(buffer, single_msg) |> st.to_string()],
      st.new(),
    )
    [first, ..rest] -> {
      let complete_parts = [st.append(buffer, first) |> st.to_string(), ..rest]
      process_port_message_parts(complete_parts, [])
    }
    [] -> #([], buffer)
  }
}

/// Process a list of port messages that are known to be at least one
/// complete payload, but may be unterminated.  
/// The overflow buffer is already appended to the first message in advance
/// so it is not included as a parameter to this function.  
/// The function may return a newly filled buffer though, if the last message was unterminated.
fn process_port_message_parts(
  parts: List(String),
  collector: List(String),
) -> #(List(String), st.StringTree) {
  case parts {
    // Last message is terminated, return the collector and an empty buffer
    [""] -> #(list.reverse(collector), st.new())
    // Last message is unterminated, return the collector and new buffer with
    // the the contents of the unterminated message
    [overflow] -> #(list.reverse(collector), st.new() |> st.append(overflow))
    // Append the current message to the collector and continue with the rest
    [cur, ..rest] -> process_port_message_parts(rest, [cur, ..collector])
    // This case should never happen, since we hancle [one] and never pass
    // an empty list, it's just to avoid the compiler error
    [] -> #(list.reverse(collector), st.new())
  }
}

type BrowserState {
  BrowserState(
    instance: BrowserInstance,
    next_id: Int,
    unanswered_requests: List(PendingRequest),
    event_listeners: List(#(String, Subject(d.Dynamic))),
    message_buffer: st.StringTree,
    shutdown_request: Option(Subject(Nil)),
    log_level: LogLevel,
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
  /// Allows you to set the log level of the running instance
  SetLogLevel(LogLevel)
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
      log_warn(
        state,
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
      log_info(state, "Event listeners: " <> string.inspect(updated_listeners))
      actor.continue(BrowserState(
        instance: state.instance,
        next_id: state.next_id,
        unanswered_requests: state.unanswered_requests,
        event_listeners: updated_listeners,
        message_buffer: state.message_buffer,
        shutdown_request: state.shutdown_request,
        log_level: state.log_level,
      ))
    }
    RemoveListener(client) -> {
      let updated_listeners =
        list.filter(state.event_listeners, fn(l) { l.1 != client })
      log_info(state, "Event listeners: " <> string.inspect(updated_listeners))
      actor.continue(BrowserState(
        instance: state.instance,
        next_id: state.next_id,
        unanswered_requests: state.unanswered_requests,
        event_listeners: updated_listeners,
        message_buffer: state.message_buffer,
        shutdown_request: state.shutdown_request,
        log_level: state.log_level,
      ))
    }
    PortResponse(data) -> {
      let #(chunks, buffer) = process_port_message(data, state.message_buffer)

      // For debugging
      case st.is_empty(buffer) {
        False -> log_info(state, "buffering browser message!")
        True -> Nil
      }

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
        log_level: state.log_level,
      ))
    }
    UnexpectedPortMessage(msg) -> {
      log_warn(
        state,
        "Got an unexpected message from the port! This should not happen!",
      )
      io.println(string.inspect(msg))
      actor.continue(state)
    }
    Shutdown(client) -> {
      // Initiate shutdown of the browser
      // the process is left hanging and should be replied to when the browser
      // has successfully shut down -> PortExit message below
      log_info(state, "Received shutdown request, attempting to quit browser")
      handle_send(state, "Browser.close", None)
      actor.continue(BrowserState(
        instance: state.instance,
        next_id: state.next_id,
        unanswered_requests: state.unanswered_requests,
        event_listeners: state.event_listeners,
        message_buffer: state.message_buffer,
        shutdown_request: Some(client),
        log_level: state.log_level,
      ))
    }
    PortExit(exit_status) -> {
      // The browser has exited
      case state.shutdown_request {
        Some(client) -> {
          log_info(
            state,
            "Browser exited after shtudown request, actor is shutting down",
          )
          process.send(client, Nil)
          actor.Stop(process.Normal)
        }
        _ -> {
          log_warn(
            state,
            "Browser exited but there was no shutdown request! Exit Status: "
              <> string.inspect(exit_status)
              <> " browser actor is shutting down abnormally",
          )
          actor.Stop(process.Abnormal(reason: "browser exited abnormally"))
        }
      }
    }
    SetLogLevel(level) -> {
      actor.continue(BrowserState(
        instance: state.instance,
        next_id: state.next_id,
        unanswered_requests: state.unanswered_requests,
        event_listeners: state.event_listeners,
        message_buffer: state.message_buffer,
        shutdown_request: state.shutdown_request,
        log_level: level,
      ))
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

  case send_to_browser(state, payload) {
    Error(_) -> {
      log_warn(state, "Request call to browser was unsuccessful!")
      process.send(client, Error(PortError))
      actor.continue(BrowserState(
        instance: state.instance,
        next_id: request_id + 1,
        unanswered_requests: state.unanswered_requests,
        event_listeners: state.event_listeners,
        message_buffer: state.message_buffer,
        shutdown_request: state.shutdown_request,
        log_level: state.log_level,
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
        log_level: state.log_level,
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
  case send_to_browser(state, payload) {
    Error(_) -> {
      log_warn(state, "Request sent to browser was unsuccessful!")
      io.println(string.inspect(payload))
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
    log_level: state.log_level,
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
    utils.find_map_remove(state.unanswered_requests, fn(req) {
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
    utils.find_map_remove(state.unanswered_requests, fn(req) {
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
      log_warn(
        state,
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
  let error_decoder = {
    use code <- decode.optional_field("code", None, decode.optional(decode.int))
    use message <- decode.optional_field("message", None, decode.optional(decode.string))
    use data <- decode.optional_field("data", None, decode.optional(decode.string))
    decode.success(RawBrowserError(code:, message:, data:))
  }
  let response_decoder = {
    use id <- decode.optional_field("id", None, decode.optional(decode.int))
    use result <- decode.optional_field("result", None, decode.optional(decode.dynamic))
    use method <- decode.optional_field("method", None, decode.optional(decode.string))
    use params <- decode.optional_field("params", None, decode.optional(decode.dynamic))
    use error <- decode.optional_field("error", None, decode.optional(error_decoder))
    decode.success(BrowserResponse(id:, result:, method:, params:, error:))
  }
  case json.parse(response, response_decoder) {
    Ok(BrowserResponse(Some(id), Some(result), None, None, None)) -> {
      // A response to a request -> should be sent to the client
      BrowserState(
        instance: state.instance,
        next_id: state.next_id,
        unanswered_requests: answer_request(state, id, result),
        event_listeners: state.event_listeners,
        message_buffer: state.message_buffer,
        shutdown_request: state.shutdown_request,
        log_level: state.log_level,
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
        log_level: state.log_level,
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
            log_debug(state, fn() {
              "Ignored Event: " <> method <> " " <> string.inspect(params)
            })
            Nil
          }
        }
      })
      state
    }
    Ok(_) -> {
      log_warn(
        state,
        "Received an unexpectedly formatted response from the browser",
      )
      io.println(string.inspect(response))
      state
    }
    Error(e) -> {
      log_warn(
        state,
        "Failed to decode data from port message, ignoring! Resonse and error:",
      )
      io.println(string.inspect(#(response, e)))
      state
    }
  }
}

// --- HELPERS ---

/// Send a JSON encoded string to the browser instance,
/// the JSON payload must already include the `id` field.
/// This function appends a null byte to the end of the message,
/// which is used by the browser to detect when a message ends.
fn send_to_browser(state: BrowserState, data: Json) {
  let payload = json.to_string(data)
  log_debug(state, fn() { "Sending Payload: " <> payload })
  send_to_port(state.instance.port, payload <> "\u{0000}")
}

fn get_first_existing_path(paths: List(String)) -> Result(String, LaunchError) {
  let existing_paths =
    paths
    |> list.filter(fn(current) {
      case file.is_file(current) {
        Ok(res) -> res
        Error(_) -> False
      }
    })

  case existing_paths {
    [first, ..] -> Ok(first)
    [] -> Error(CouldNotFindExecutable)
  }
}

@internal
pub fn resolve_env_cofig() -> Result(BrowserConfig, Nil) {
  use path <- result.try(envoy.get("CHROBOT_BROWSER_PATH"))
  let args = case envoy.get("CHROBOT_BROWSER_ARGS") {
    Ok(args_string) -> string.split(args_string, "\n")
    Error(Nil) -> get_default_chrome_args()
  }
  let time_out = case envoy.get("CHROBOT_BROWSER_TIMEOUT") {
    Ok(timeout_string) ->
      result.unwrap(int.parse(timeout_string), default_timeout)
    Error(Nil) -> default_timeout
  }
  let log_level = case envoy.get("CHROBOT_LOG_LEVEL") {
    Ok("silent") -> LogLevelSilent
    Ok("warnings") -> LogLevelWarnings
    Ok("info") -> LogLevelInfo
    Ok("debug") -> LogLevelDebug
    Ok(_) -> LogLevelWarnings
    Error(Nil) -> LogLevelWarnings
  }

  Ok(BrowserConfig(
    path: path,
    args: args,
    start_timeout: time_out,
    log_level: log_level,
  ))
}

fn log_info(state: BrowserState, message: String) {
  case state.log_level {
    LogLevelInfo | LogLevelDebug -> {
      io.println("[INFO] " <> string.inspect(state.instance) <> ": " <> message)
    }
    _ -> Nil
  }
}

fn log_warn(state: BrowserState, message: String) {
  case state.log_level {
    LogLevelInfo | LogLevelDebug | LogLevelWarnings -> {
      io.println(
        "[WARNING] " <> string.inspect(state.instance) <> ": " <> message,
      )
    }
    _ -> Nil
  }
}

/// Debug is called lazily, to avoid doing work constructing strings
/// for it that never get used
fn log_debug(state: BrowserState, callback: fn() -> String) {
  case state.log_level {
    LogLevelDebug -> {
      io.println(
        "[DEBUG] " <> string.inspect(state.instance) <> ": " <> callback(),
      )
    }
    _ -> Nil
  }
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
