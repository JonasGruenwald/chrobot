//// Welcome to Chrobot! 🤖
//// This module exposes high level functions for browser automation.
//// 
//// Some basic concepts:
//// 
//// 1. You want to `launch` an instance of the browser and receive a `Subject` which allows
//// you to send messages to the browser (actor)
//// 2. You can `open` a `Page`, which makes the browser browse to a website  
//// -> Hold on to the returned `Page`, most useful operations will require it as a parameter
//// 3. When you are done with the browser, you should call `quit` to shut it down gracefully
//// 
//// The rest should hopefully be self-evident from the documentation of this module's functions.
//// 
//// A brief explanation of the abstractions in this module, in case you need to make raw protocol calls:  
//// In CDP the way to interact with websites is by creating a target and attaching to it, which spawns
//// a session with a `sessionId`. It's only possible to interact with domains like the dom domain,
//// if you pass this `sessionId` with your protocol call.  
//// Confusingly, if you forget to provide a `sessionId` to a method like `DOM.getDocument`, the error response 
//// will tell you that no such method exists - it does though, you just need to provide a `sessionId` when calling it.
//// When you call `open` in this module, the steps of creating a target and session are taken for you, 
//// and stored in the returned `Page` type along with the browser subject.
//// When you make raw protocol calls, be sure to provide a `sessionId`!

import chrome
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import protocol
import protocol/dom
import protocol/target

/// Holds information about the current page,
/// as well as the desired timeout in milliseconds
/// to use when waiting for browser responses.
pub type Page {
  Page(
    browser: Subject(chrome.Message),
    time_out: Int,
    target_id: target.TargetID,
    session_id: target.SessionID,
    root_node: dom.Node,
  )
}

/// Try to find a chrome installation and launch it with default arguments.
/// 
/// First, it will try to find a local chrome installation, like that created by `npx @puppeteer/browsers install chrome`
/// If that fails, it will try to find a system chrome installation in some common places.  
/// Consider using `launch_with_config` with a `BrowserConfig` instead and specifying 
/// an explicit path to the chrome executable if consistency is a requirement.
/// 
/// This function will validate that the browser launched successfully, and the 
/// protocol version matches the one supported by this library.
pub fn launch() {
  let launch_result = validate_launch(chrome.launch())

  // Some helpful logging for when the browser could not be found
  case launch_result {
    Error(chrome.CouldNotFindExecutable) -> {
      io.println(
        "\u{1b}[31mChrobot could not find a chrome executable to launch!\u{1b}[0m",
      )
      io.println("\u{1b}[36m")
      io.println(
        "ℹ️  Hint: Consider installing Chrome for Testing from puppeteer:",
      )
      io.println("npx @puppeteer/browsers install chrome")
      io.println("\u{1b}[0m ")
      launch_result
    }
    other -> other
  }
}

/// Open a page and wait for the document to resolve.  
/// Note that the timeout can't be considered strict in the current implementation,  
/// this call specifically may take longer than the specified timeout.
pub fn open(
  browser_subject: Subject(chrome.Message),
  url: String,
  time_out: Int,
) -> Result(Page, chrome.RequestError) {
  use target_response <- result.try(target.create_target(
    fn(method, params) {
      chrome.call(browser_subject, method, params, None, time_out)
    },
    url,
    None,
    None,
    None,
    None,
  ))

  use session_response <- result.try(target.attach_to_target(
    fn(method, params) {
      chrome.call(browser_subject, method, params, None, time_out)
    },
    target_response.target_id,
    Some(True),
  ))

  // TODO we need to wait until the DOM is ready here somehow

  // Wait until document resolves
  let poll_result =
    poll(
      fn() {
        // TODO NO!!! we can't poll get_document because it will make the browser node IDs change which will cause a ton of issues
        // I think we should first wait for this:  Page.loadEventFired # 
        dom.get_document(
          fn(method, params) {
            chrome.call(
              browser_subject,
              method,
              params,
              pass_session(session_response.session_id),
              time_out,
            )
          },
          None,
          None,
        )
      },
      time_out,
    )

  // Return document or last poll error before timeout
  case poll_result {
    Ok(document) ->
      Ok(Page(
        browser: browser_subject,
        session_id: session_response.session_id,
        target_id: target_response.target_id,
        time_out: time_out,
        root_node: document.root,
      ))
    Error(any) -> Error(any)
  }
}

/// Run a query selector on document node of the current page
/// and return the first result
pub fn select(
  page: Page,
  selector: String,
) -> Result(dom.NodeId, chrome.RequestError) {
  use result <- result.try(dom.query_selector(
    page_caller(page),
    page.root_node.node_id,
    selector,
  ))
  Ok(result.node_id)
}

pub fn select_all(page: Page) {
  todo
}

/// Return an updated `Page` with the desired timeout to apply, in milliseconds
pub fn with_timeout(page: Page, time_out) {
  Page(page.browser, time_out, page.target_id, page.session_id, page.root_node)
}

/// Launch a browser with the given configuration,
/// to populate the arguments, use `browser.get_default_chrome_args`.
/// This function will validate that the browser launched successfully, and the 
/// protocol version matches the one supported by this library.
/// 
/// ## Example
/// ```gleam
/// let config =
/// browser.BrowserConfig(
///   path: "chrome/linux-116.0.5793.0/chrome-linux64/chrome",
///   args: chrome.get_default_chrome_args(),
///   start_timeout: 5000,
/// )
/// let assert Ok(browser_subject) = launch_with_config(config)
/// ```
pub fn launch_with_config(config: chrome.BrowserConfig) {
  validate_launch(chrome.launch_with_config(config))
}

/// Validate that the browser responds to protocol messages, 
/// and that the protocol version matches the one supported by this library.
fn validate_launch(
  launch_result: Result(Subject(chrome.Message), chrome.LaunchError),
) {
  use instance <- result.try(launch_result)
  let #(major, minor) = protocol.version()
  let target_protocol_version = major <> "." <> minor
  let version_response =
    chrome.get_version(instance)
    |> result.replace_error(chrome.UnresponsiveAfterStart)
  use actual_version <- result.try(version_response)
  case target_protocol_version == actual_version.protocol_version {
    True -> Ok(instance)
    False ->
      Error(chrome.ProtocolVersionMismatch(
        target_protocol_version,
        actual_version.protocol_version,
      ))
  }
}

/// Quit the browser (alias for `chrome.quit`)
pub fn quit(browser: Subject(chrome.Message)) {
  chrome.quit(browser)
}

/// Convenience function that lets you defer quitting the browser after you are done with it,
/// it's meant for a `use` expression like this:
/// 
/// ```gleam
/// let assert Ok(browser_subject) = browser.launch()
/// use <- browser.defer_quit(browser_subject)
/// // do stuff with the browser
/// ```
pub fn defer_quit(browser: Subject(chrome.Message), body) {
  body()
  chrome.quit(browser)
}

// ---- UTILS
const poll_interval = 100

/// Periodically try to call the function until it returns a 
/// result instead of an error.
/// Note: doesn't handle elapsed time during function call attempt yet
/// TODO measure time elapsed during function call and take it into account
fn poll(callback: fn() -> Result(a, b), remaining_time: Int) -> Result(a, b) {
  case callback() {
    Ok(a) -> Ok(a)
    Error(b) if poll_interval <= 0 -> {
      Error(b)
    }
    Error(_) -> {
      process.sleep(poll_interval)
      poll(callback, remaining_time - poll_interval)
    }
  }
}

/// Cast a session in the target.SessionID type to the 
/// string expected by the `chrome` module
fn pass_session(session_id: target.SessionID) -> Option(String) {
  case session_id {
    target.SessionID(value) -> Some(value)
  }
}

/// Create callback to pass to protocol commands from a `Page` 
pub fn page_caller(page: Page) {
  fn(method, params) {
    chrome.call(
      page.browser,
      method,
      params,
      pass_session(page.session_id),
      page.time_out,
    )
  }
}
