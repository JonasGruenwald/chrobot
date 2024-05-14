//// Welcome to Chrobot! 🤖
//// This module exposes high level functions for browser automation.
//// 
//// Some basic concepts:
//// 
//// - You'll first want to `launch` an instance of the browser and receive a `Subject` which allows
//// you to send messages to the browser (actor)
//// - You can `open` a `Page`, which makes the browser browse to a website, hold on to the returned `Page`, and pass it to functions in this module
//// - If you want to make raw protocol calls, you can use `page_caller`, to create a callback to pass to protocol commands from your `Page`
//// - When you are done with the browser, you should call `quit` to shut it down gracefully
//// 
//// 
//// 

import chrome
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import protocol
import protocol/page
import protocol/runtime
import protocol/target
import simplifile as file

/// Holds information about the current page,
/// as well as the desired timeout in milliseconds
/// to use when waiting for browser responses.
pub type Page {
  Page(
    browser: Subject(chrome.Message),
    time_out: Int,
    target_id: target.TargetID,
    session_id: target.SessionID,
  )
}

pub type EncodedFile {
  EncodedFile(data: String, extension: String)
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

/// Open a page and wait for the document to resolve.  
/// Returns a response only when `Page.loadEventFired` is received, you
/// can additionally use `await_selector` to ensure the page is ready with the 
/// content you expect.
pub fn open(
  with browser_subject: Subject(chrome.Message),
  to url: String,
  time_out time_out: Int,
) -> Result(Page, chrome.RequestError) {
  use target_response <- result.try(target.create_target(
    fn(method, params) {
      chrome.call(browser_subject, method, params, None, time_out)
    },
    url,
    Some(1920),
    Some(1080),
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

  // Enable Page domain to receive events like ` Page.loadEventFired`
  use _ <- result.try(
    page.enable(fn(method, params) {
      chrome.call(
        browser_subject,
        method,
        params,
        pass_session(session_response.session_id),
        time_out,
      )
    }),
  )

  // Wait for the load event to fire
  use _ <- result.try(chrome.listen_once(
    browser_subject,
    "Page.loadEventFired",
    time_out,
  ))

  // I noticed with about:blank the load event never fires
  // maybe it's because the page is loaded to quick and there is a race condition?
  // we could remove this 'waiting for the load event to fire' step in favour
  // of just always using the await selector, which works pretty well I think

  // Return the page
  Ok(Page(
    browser: browser_subject,
    session_id: session_response.session_id,
    target_id: target_response.target_id,
    time_out: time_out,
  ))
}

/// Similar to `open`, but creates a new page from HTML that you pass to it.
/// The page will be created under the `about:blank` URL.
pub fn create_page(
  with browser: Subject(chrome.Message),
  from html: String,
  time_out time_out: Int,
) {
  use target_response <- result.try(target.create_target(
    fn(method, params) { chrome.call(browser, method, params, None, time_out) },
    "about:blank",
    Some(1920),
    Some(1080),
    None,
    None,
  ))

  use session_response <- result.try(target.attach_to_target(
    fn(method, params) { chrome.call(browser, method, params, None, time_out) },
    target_response.target_id,
    Some(True),
  ))

  let created_page =
    Page(
      browser: browser,
      session_id: session_response.session_id,
      target_id: target_response.target_id,
      time_out: time_out,
    )

  use _ <- result.try(await_selector(created_page, "body"))

  io.debug("page")
  let payload = "window.document.open();
window.document.write(`" <> html <> "`);
window.document.close();
"
  use _ <- result.try(eval(created_page, payload))
  Ok(created_page)
}

/// Return an updated `Page` with the desired timeout to apply, in milliseconds
pub fn with_timeout(page: Page, time_out) {
  Page(page.browser, time_out, page.target_id, page.session_id)
}

/// Capture a screenshot of the current page and return it as a base64 encoded string
/// The Ok(result) of this function can be passed to `to_file`  
///   
/// If you want to customize the settings of the output image, use `capture_screenshot` from `protocol/page` directly
pub fn screenshot(page: Page) -> Result(EncodedFile, chrome.RequestError) {
  use response <- result.try(page.capture_screenshot(
    page_caller(page),
    format: Some(page.CaptureScreenshotFormatPng),
    quality: None,
    clip: None,
  ))

  Ok(EncodedFile(data: response.data, extension: "png"))
}

/// Export the current page as PDF and return it as a base64 encoded string.  
/// Transferring the encoded file from the browser to the chrome agent can take a pretty long time,
/// depending on the document size.  
/// Consider setting a larger timeout, you can use `with_timeout` on your existing `Page` to do this.
/// The Ok(result) of this function can be passed to `to_file`  
///   
/// If you want to customize the settings of the output document, use `print_to_pdf` from `protocol/page` directly
pub fn pdf(page: Page) -> Result(EncodedFile, chrome.RequestError) {
  use response <- result.try(page.print_to_pdf(
    page_caller(page),
    landscape: Some(False),
    display_header_footer: Some(False),
    // use the defaults for everything
    print_background: None,
    scale: None,
    paper_width: None,
    paper_height: None,
    margin_top: None,
    margin_bottom: None,
    margin_left: None,
    margin_right: None,
    page_ranges: None,
    header_template: None,
    footer_template: None,
    prefer_css_page_size: None,
  ))

  Ok(EncodedFile(data: response.data, extension: "pdf"))
}

// Write an file returned from `screenshot` of `pdf` to a file.
// File path should not include the file extension, it will be appended automatically.
// Will return a FileError from the `simplifile` package if not successfull
pub fn to_file(
  input input: EncodedFile,
  path path: String,
) -> Result(Nil, file.FileError) {
  let res =
    bit_array.base64_decode(input.data)
    |> result.replace_error(file.Unknown)

  use binary <- result.try(res)
  file.write_bits(to: path <> "." <> input.extension, bits: binary)
}

/// Evaluate some JavaScript on the page and return the result,
/// which will be a `RemoteObject` reference.  
/// Check the `protocol/runtime` module for more info.
pub fn eval(on page: Page, js expression: String) {
  runtime.evaluate(
    page_caller(page),
    expression: expression,
    object_group: None,
    include_command_line_api: None,
    silent: Some(False),
    // will be the current page by default
    context_id: None,
    return_by_value: Some(False),
    user_gesture: Some(True),
    await_promise: Some(False),
  )
  |> handle_eval_response()
}

/// Like `eval`, but awaits for the result of the evaluation
/// and returns once promise has been resolved
pub fn eval_async(on page: Page, js expression: String) {
  runtime.evaluate(
    page_caller(page),
    expression: expression,
    object_group: None,
    include_command_line_api: None,
    silent: Some(False),
    // will be the current page by default
    context_id: None,
    return_by_value: Some(False),
    user_gesture: Some(True),
    await_promise: Some(True),
  )
  |> handle_eval_response()
}

pub fn select(on page: Page, select selector: String) {
  let selector_code = "window.document.querySelector(\"" <> selector <> "\")"
  eval(page, selector_code)
}

/// Continously attempt to run a selector, until it succeeds.  
/// You can use this after opening a page, to wait for the moment it has initialized
/// enough sufficiently for you to run your automation on it.
pub fn await_selector(on page: Page, select selector: String) {
  // 🦜
  let polly = fn() {
    let result =
      eval(page, "window.document.querySelector(\"" <> selector <> "\")")
    case result {
      Ok(runtime.RemoteObject(_, _, _, _, _, _, Some(_remote_object_id))) -> {
        Ok(result)
      }
      Ok(_) -> {
        Error(chrome.NotFoundError)
      }
      Error(any) -> Error(any)
    }
  }
  poll(polly, page.time_out)
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

// TODO measure time elapsed during function call and take it into account
/// Periodically try to call the function until it returns a 
/// result instead of an error.
/// Note: doesn't handle elapsed time during function call attempt yet
fn poll(callback: fn() -> Result(a, b), remaining_time: Int) -> Result(a, b) {
  case callback() {
    Ok(a) -> Ok(a)
    Error(b) if remaining_time <= 0 -> {
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

fn handle_eval_response(eval_response) {
  case eval_response {
    Ok(runtime.EvaluateResponse(result: _, exception_details: Some(exception))) -> {
      Error(chrome.RuntimeException(
        text: exception.text,
        line: exception.line_number,
        column: exception.column_number,
      ))
    }
    Ok(runtime.EvaluateResponse(result: result_data, exception_details: None)) -> {
      Ok(result_data)
    }
    Error(other) -> Error(other)
  }
}
