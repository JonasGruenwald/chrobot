import chrome
import gleam/io
import gleam/result
import gleeunit
import utils

/// The tests will only run if a browser path is set in the environment variable `CHROBOT_TEST_BROWSER_PATH`.
pub fn main() {
  let test_browser_path = utils.try_get_browser_path()
  case test_browser_path {
    Ok(browser_path) -> {
      io.println("Using test browser: " <> browser_path)
      gleeunit.main()
    }
    Error(_) -> {
      io.println(
        "\u{1b}[31mNo test browser path was set! Please set the environment variable `CHROBOT_TEST_BROWSER_PATH` to run the tests.\u{1b}[0m",
      )
      let available_browser_path =
        result.lazy_or(
          chrome.get_local_chrome_path(),
          chrome.get_system_chrome_path,
        )
      case available_browser_path {
        Ok(browser_path) -> {
          io.println("\u{1b}[36m")
          io.println(
            "ℹ️  Hint: A chrome path was detected on your system, you can run tests like this:",
          )
          io.println(
            "CHROBOT_TEST_BROWSER_PATH=\"" <> browser_path <> "\" gleam test\n",
          )
          io.println("\u{1b}[0m ")
        }
        Error(_) -> {
          io.println("\u{1b}[36m")
          io.println(
            "ℹ️  Hint: Consider installing Chrome for Testing from puppeteer:",
          )
          io.println("npx @puppeteer/browsers install chrome")
          io.println("\u{1b}[0m ")
        }
      }
      panic as "See output above!"
    }
  }
}
