import browser
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/result
import protocol

/// Try to find a chrome installation and launch it with default arguments.
/// 
/// First, it will try to find a local chrome installation, like that created by `npx @puppeteer/browsers install chrome`
/// If that fails, it will try to find a system chrome installation in some common places.
/// 
/// This function will validate that the browser launched successfully, and the 
/// protocol version matches the one supported by this library.
/// 
/// For consistency it would be preferrable to not use this function and instead use `launch_with_config` with a `BrowserConfig`
/// that specifies the path to the chrome executable.
/// 
/// 
pub fn launch() {
  validate_launch(browser.launch())
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
///   args: browser.get_default_chrome_args(),
///   start_timeout: 5000,
/// )
/// let assert Ok(browser_subject) = launch_with_config(config)
/// ```
pub fn launch_with_config(config: browser.BrowserConfig) {
  validate_launch(browser.launch_with_config(config))
}

/// Validate that the browser responds to protocola messages, 
/// and that the protocol version matches the one supported by this library.
fn validate_launch(
  launch_result: Result(Subject(browser.Message), browser.LaunchError),
) {
  use instance <- result.try(launch_result)
  let #(major, minor) = protocol.version()
  let target_protocol_version = major <> "." <> minor
  let version_response =
    browser.get_version(instance)
    |> result.replace_error(browser.UnresponsiveAfterStart)
  use actual_version <- result.try(version_response)
  case target_protocol_version == actual_version.protocol_version {
    True -> Ok(instance)
    False -> Error(browser.ProtocolVersionMismatch)
  }
}
