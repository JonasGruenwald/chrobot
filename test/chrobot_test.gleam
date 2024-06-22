import birdie
import chrobot
import chrobot/internal/utils
import chrome
import gleam/dynamic
import gleam/erlang/process
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

  chrobot.await_selector(page, "#wibble")
  |> should.be_ok()

  chrobot.get_all_html(page)
  |> should.be_ok()
  |> birdie.snap(title: "Opened Sample Page")
}

pub fn create_page_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let reference_html = test_utils.get_reference_html()
  let page = should.be_ok(chrobot.create_page(browser, reference_html, 10_000))

  chrobot.get_all_html(page)
  |> should.be_ok()
  |> birdie.snap(title: "Created Page with Reference HTML")
}

pub fn eval_test() {
  use page <- test_utils.with_reference_page()
  let expression = "2 * Math.PI"
  chrobot.eval(page, expression)
  |> chrobot.as_value(dynamic.float)
  |> should.be_ok()
  |> should.equal(6.283185307179586)
}

pub fn eval_async_test() {
  use page <- test_utils.with_reference_page()
  let expression =
    "new Promise((resolve, reject) => setTimeout(() => resolve(42), 50))"
  chrobot.eval_async(page, expression)
  |> chrobot.as_value(dynamic.int)
  |> should.be_ok()
  |> should.equal(42)
}

pub fn eval_async_failure_test() {
  use page <- test_utils.with_reference_page()
  let expression = "Promise.reject(new Error('This is a test error'))"
  let result = chrobot.eval_async(page, expression)
  case result {
    Error(chrome.RuntimeException(text: text, column: column, line: line)) -> {
      text
      |> should.equal("Uncaught (in promise) Error: This is a test error")
      column
      |> should.equal(0)
      line
      |> should.equal(0)
    }
    other -> {
      utils.err(
        "Expected a chrome.RuntimeException, got: \n" <> string.inspect(other),
      )
      panic as "Test failed! the result was not a chrome.RuntimeException!"
    }
  }
}

pub fn await_selector_test() {
  use page <- test_utils.with_reference_page()
  chrobot.await_selector(page, "body")
  |> should.be_ok()
}

pub fn await_selector_failure_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let reference_html = test_utils.get_reference_html()
  let page =
    chrobot.create_page(browser, reference_html, 10_000)
    |> should.be_ok()
    |> chrobot.with_timeout(100)

  chrobot.await_selector(page, "#bogus")
  |> should.be_error()
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

pub fn poll_test() {
  let initial_time = utils.get_time_ms()

  // this function will start returning "Success" in 200ms
  let poll_function = fn() {
    case utils.get_time_ms() - initial_time {
      time if time > 200 -> Ok("Success")
      _ -> Error(chrome.NotFoundError)
    }
  }

  chrobot.poll(poll_function, 500)
  |> should.be_ok()
  |> should.equal("Success")
}

pub fn poll_failure_test() {
  let initial_time = utils.get_time_ms()

  // this function will start returning "Success" in 200ms
  let poll_function = fn() {
    case utils.get_time_ms() - initial_time {
      time if time > 200 -> Ok("Success")
      _ -> Error(chrome.NotFoundError)
    }
  }

  case chrobot.poll(poll_function, 100) {
    Error(chrome.NotFoundError) -> {
      should.be_true(True)
      let elapsed_time = utils.get_time_ms() - initial_time
      // timeout should be within a 10ms window of accuracy
      { elapsed_time < 105 && elapsed_time > 95 }
      |> should.be_true()
    }
    _ -> {
      utils.err("Polling function didn't return the correct error")
      should.fail()
    }
  }
}

pub fn poll_timeout_failure_test() {
  let initial_time = utils.get_time_ms()

  // this function will return errors first
  // and after 100ms it will start blocking for 10s
  let poll_function = fn() {
    case utils.get_time_ms() - initial_time {
      time if time > 100 -> {
        process.sleep(10_000)
        Ok("Success")
      }
      _ -> Error(chrome.NotFoundError)
    }
  }

  // the timeout is 300ms, so the polling function will be interrupted
  // while it's blocking, it should still return the original error
  case chrobot.poll(poll_function, 300) {
    Error(chrome.NotFoundError) -> {
      should.be_true(True)
      let elapsed_time = utils.get_time_ms() - initial_time
      // timeout should be within a 10ms window of accuracy
      { elapsed_time < 305 && elapsed_time > 295 }
      |> should.be_true()
    }
    _ -> {
      utils.err("Polling function didn't return the correct error")
      should.fail()
    }
  }
}
