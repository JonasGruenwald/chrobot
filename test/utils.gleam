//// Shared test utilities

import gleam/erlang/os

/// Try to get the path to the browser to use for tests
/// If the CHROBOT_TEST_BROWSER_PATH environment variable is not set, this will return an error
/// -> use in test setup to validate that the environment variable is set
pub fn try_get_browser_path() {
  os.get_env("CHROBOT_TEST_BROWSER_PATH")
}

/// Get the path to the browser to use for tests
/// If the CHROBOT_TEST_BROWSER_PATH environment variable is not set, this will panic
/// -> use in tests to get the browser path
/// -> we can assume that the environment variable is set, as we have already validated it in the test setup
pub fn get_browser_path() {
  let assert Ok(browser_path) = try_get_browser_path()
  browser_path
}
