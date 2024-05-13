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
import gleam/result
import protocol
import protocol/target

/// This type abstracts some 
pub type Page {
  Page(
    browser: Subject(chrome.Message),
    target_id: target.TargetID,
    session_id: target.SessionID,
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
