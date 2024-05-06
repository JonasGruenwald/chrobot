import browser
import gleam/erlang/process
import gleam/io

pub fn main() {
  // let config =
  //   browser.BrowserConfig(
  //     path: "/Users/jonas/Projects/chrobot/chrome/mac_arm-126.0.6458.0/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
  //     args: browser.get_default_chrome_args(),
  //     start_timeout: 5000,
  //   )
  // let assert Ok(browser_subject) = browser.launch_with_config(config)
  let assert Ok(browser_subject) = browser.launch()
  let assert Ok(version) = browser.get_version(browser_subject)
  io.debug(#("version: ", version))
  process.sleep_forever()
}
