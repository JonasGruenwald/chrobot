import chrome
import gleam/erlang/process.{type Subject}
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
  validate_launch(chrome.launch())
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
