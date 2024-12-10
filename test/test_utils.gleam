//// Shared test utilities

import chrobot
import chrobot/chrome
import gleeunit/should
import simplifile as file
import envoy

/// Try to get the path to the browser to use for tests
/// If the CHROBOT_TEST_BROWSER_PATH environment variable is not set, this will return an error
/// -> use in test setup to validate that the environment variable is set
pub fn try_get_browser_path() {
  envoy.get("CHROBOT_TEST_BROWSER_PATH")
}

/// Get the path to the browser to use for tests
/// If the CHROBOT_TEST_BROWSER_PATH environment variable is not set, this will panic
/// -> use in tests to get the browser path
/// -> we can assume that the environment variable is set, as we have already validated it in the test setup
pub fn get_browser_path() {
  let assert Ok(browser_path) = try_get_browser_path()
  browser_path
}

pub fn get_browser_instance() {
  let browser_path = get_browser_path()
  let config =
    chrome.BrowserConfig(
      path: browser_path,
      args: chrome.get_default_chrome_args(),
      start_timeout: 5000,
      log_level: chrome.LogLevelWarnings,
    )
  let browser = should.be_ok(chrome.launch_with_config(config))
  browser
}

/// for use with a use expression
pub fn with_reference_page(apply fun) {
  let browser = get_browser_instance()
  let reference_html = get_reference_html()
  let assert Ok(page) = chrobot.create_page(browser, reference_html, 10_000)
  should.be_ok(chrobot.await_selector(page, "body"))
  fun(page)
  chrobot.quit(browser)
}

pub fn get_reference_html() {
  let assert Ok(content) = file.read("test_assets/reference_website.html")
  content
}
