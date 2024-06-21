import birdie
import chrobot
import chrobot/internal/utils
import chrome
import gleam/dynamic
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleeunit
import gleeunit/should
import test_server
import test_utils

/// TEST SETUP
/// The tests will only run if a browser path is set in the environment variable `CHROBOT_TEST_BROWSER_PATH`.
pub fn main() {
  let test_browser_path = test_utils.try_get_browser_path()
  test_server.start()

  case test_browser_path {
    Ok(browser_path) -> {
      io.println("Using test browser: " <> browser_path)
      gleeunit.main()
    }
    Error(_) -> {
      utils.err(
        "No test browser path was set! Please set the environment variable `CHROBOT_TEST_BROWSER_PATH` to run the tests.\n",
      )
      let available_browser_path =
        result.lazy_or(
          chrome.get_local_chrome_path(),
          chrome.get_system_chrome_path,
        )
      case available_browser_path {
        Ok(browser_path) -> {
          utils.hint(
            "A chrome path was detected on your system, you can run tests like this:",
          )
          utils.show_cmd(
            "CHROBOT_TEST_BROWSER_PATH=\"" <> browser_path <> "\" gleam test\n",
          )
        }
        Error(_) -> {
          utils.hint(
            "Consider installing a local version of chrome for the project:",
          )
          utils.show_cmd("gleam run -m browser_install")
        }
      }
      panic as "See output above!"
    }
  }
}

pub fn open_test() {
  let browser = test_utils.get_browser_instance()
  let test_url = test_server.get_url()
  use <- chrobot.defer_quit(browser)

  let page =
    chrobot.open(browser, test_url, 10_000)
    |> should.be_ok()

  chrobot.await_selector(page, "body")
  |> should.be_ok()

  chrobot.eval(page, "window.location.href")
  |> chrobot.as_value(dynamic.string)
  |> should.be_ok()
  |> should.equal(test_url)
}

pub fn create_page_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let reference_html = test_utils.get_reference_html()
  let _page = should.be_ok(chrobot.create_page(browser, reference_html, 10_000))
}

pub fn await_selector_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let reference_html = test_utils.get_reference_html()
  let page = should.be_ok(chrobot.create_page(browser, reference_html, 10_000))
  should.be_ok(chrobot.await_selector(page, "body"))
}

pub fn get_all_html_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let dummy_html =
    "<html><body>
  <p>
  I am HTML 
  </p>
  <p>
  I am the hyperstructure 
  </p>
  <p>
  I am linked to you 
  </p>
  </body></html>"
  let page =
    chrobot.create_page(browser, dummy_html, 10_000)
    |> should.be_ok()
  let result =
    chrobot.get_all_html(page)
    |> should.be_ok()
  birdie.snap(result, title: "Outer HTML")
}

pub fn select_test() {
  use page <- test_utils.with_reference_page()
  let object_id =
    chrobot.select(page, "#wibble")
    |> should.be_ok
  let text_content =
    chrobot.get_text(page, object_id)
    |> should.be_ok()

  text_content
  |> should.equal("Wibble")
}

pub fn get_html_test() {
  use page <- test_utils.with_reference_page()
  let object =
    chrobot.select(page, "header")
    |> should.be_ok

  let inner_html =
    chrobot.get_inner_html(page, object)
    |> should.be_ok

  let outer_html =
    chrobot.get_outer_html(page, object)
    |> should.be_ok

  birdie.snap(inner_html, title: "Element Inner HTML")
  birdie.snap(outer_html, title: "Element Outer HTML")
}

pub fn get_attribute_test() {
  use page <- test_utils.with_reference_page()
  let object_id =
    chrobot.select(page, "#wobble")
    |> should.be_ok

  let attribute =
    chrobot.get_attribute(page, object_id, "data-foo")
    |> should.be_ok

  attribute
  |> should.equal("bar")
}

pub fn select_all_test() {
  use page <- test_utils.with_reference_page()
  let object_ids =
    chrobot.select_all(page, "a")
    |> should.be_ok

  let hrefs =
    object_ids
    |> list.map(fn(object_id) {
      chrobot.get_attribute(page, object_id, "href")
      |> should.be_ok
    })

  birdie.snap(string.join(hrefs, "\n"), title: "List of links")
}

pub fn get_property_test() {
  use page <- test_utils.with_reference_page()
  let object_id =
    chrobot.select(page, "#demo-checkbox")
    |> should.be_ok

  chrobot.get_property(page, object_id, "checked", dynamic.bool)
  |> should.be_ok
  |> should.be_true
}

pub fn click_test() {
  use page <- test_utils.with_reference_page()

  // This is just a sanity check, to make sure the checkbox is checked before we click it
  let object_id =
    chrobot.select(page, "#demo-checkbox")
    |> should.be_ok

  chrobot.get_property(page, object_id, "checked", dynamic.bool)
  |> should.be_ok
  |> should.be_true

  // Click the checkbox
  chrobot.click(page, object_id)
  |> should.be_ok

  // After clicking the checkbox, it should be unchecked
  chrobot.get_property(page, object_id, "checked", dynamic.bool)
  |> should.be_ok
  |> should.be_false
}

pub fn type_test() {
  use page <- test_utils.with_reference_page()
  let object_id =
    chrobot.select(page, "#demo-text-input")
    |> should.be_ok

  chrobot.focus(page, object_id)
  |> should.be_ok

  chrobot.type_text(page, "Hello, World!")
  |> should.be_ok

  chrobot.get_property(page, object_id, "value", dynamic.string)
  |> should.be_ok
  |> should.equal("Hello, World!")
}

pub fn press_key_test() {
  use page <- test_utils.with_reference_page()
  let object_id =
    chrobot.select(page, "#demo-text-input")
    |> should.be_ok

  chrobot.focus(page, object_id)
  |> should.be_ok

  chrobot.press_key(page, "Enter")
  |> should.be_ok

  chrobot.get_property(page, object_id, "value", dynamic.string)
  |> should.be_ok
  |> should.equal("ENTER KEY PRESSED")
}
