//// Welcome to Chrobot! 🤖
//// This module exposes high level functions for browser automation.
//// 
//// Some basic concepts:
//// 
//// - You'll first want to [`launch`](#launch) an instance of the browser and receive a `Subject` which allows
//// you to send messages to the browser (actor)
//// - You can [`open`](#open) a [`Page`](#Page), which makes the browser browse to a website
//// - Use [`await_selector`](#await_selector) to wait for an element to appear on the page before you interact with it!
//// - You can interact with the page by calling functions in this module with the [`Page`](#Page) you received from [`open`](#open)
//// - For extracting information from the page, select elements with [`select`](#select) or [`select_all`](#select_all), 
////   then use [`get_text`](#get_text), [`get_attribute`](#get_attribute), [`get_property`](#get_property) or [`get_inner_html`](#get_inner_html)
//// - To simulate user input, use [`press_key`](#press_key), [`type_text`](#type_text), [`click`](#click) and [`focus`](#focus)
//// - If you want to make raw protocol calls, you can use [`page_caller`](#page_caller), to create a callback to pass to protocol commands from your [`Page`](#Page)
//// - When you are done with the browser, you should call [`quit`](#quit) to shut it down gracefully
//// 
//// The functions in this module just make calls to [`protocol/`](/chrobot/protocol.html)  modules, if you
//// would like to customize the behaviour, take a look at them to see how to make
//// direct protocol calls and pass different defaults.  
////  
//// Something to consider:  
//// A lot of the functions in this module are interpolating their parameters into  
//// JavaScript expressions that are evaluated in the page context.  
//// No attempt is made to escape the passed parameters or prevent script injection through them, 
//// you should not use the functions in this module with arbitrary strings if you want
//// to treat the pages you are operating on as a secure context.
//// 

import chrobot/internal/keymap
import chrobot/internal/utils
import chrome.{type RequestError}
import gleam/bit_array
import gleam/bool
import gleam/dynamic
import gleam/erlang/process.{type Subject}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/task
import gleam/result
import gleam/string
import protocol
import protocol/input
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

/// Holds a base64 encoded file and its extension
pub type EncodedFile {
  EncodedFile(data: String, extension: String)
}

/// ✨Cleverly✨ try to find a chrome installation and launch it with reasonable defaults.
/// 
/// 1. If `CHROBOT_BROWSER_PATH` is set, use that
/// 2. If a local chrome installation is found, use that
/// 3. If a system chrome installation is found, use that
/// 4. If none of the above, return an error
/// 
/// If you want to always use a specific chrome installation, take a look at [`launch_with_config`](#launch_with_config) or 
/// [`launch_with_env`](#launch_with_env) to set the path explicitly.
/// 
/// This function will validate that the browser launched successfully, and the 
/// protocol version matches the one supported by this library.
pub fn launch() -> Result(Subject(chrome.Message), chrome.LaunchError) {
  let launch_result = validate_launch(chrome.launch())

  // Some helpful logging for when the browser could not be found
  case launch_result {
    Error(chrome.CouldNotFindExecutable) -> {
      utils.err("Chrobot could not find a chrome executable to launch!\n")
      utils.hint(
        "You can install a local version of chrome for testing with this command:",
      )
      utils.show_cmd("gleam run -m browser_install")
      launch_result
    }
    other -> other
  }
}

/// Like [`launch`](#launch), but launches the browser with a visible window, not
/// in headless mode, which is useful for debugging and development.  
pub fn launch_window() -> Result(Subject(chrome.Message), chrome.LaunchError) {
  let launch_result = validate_launch(chrome.launch_window())

  // Some helpful logging for when the browser could not be found
  case launch_result {
    Error(chrome.CouldNotFindExecutable) -> {
      utils.err("Chrobot could not find a chrome executable to launch!\n")
      utils.hint(
        "You can install a local version of chrome for testing with this command:",
      )
      utils.show_cmd("gleam run -m browser_install")
      launch_result
    }
    other -> other
  }
}

/// Launch a browser with the given configuration,
/// to populate the arguments, use [`chrome.get_default_chrome_args`](/chrobot/chrome.html#get_default_chrome_args).
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
pub fn launch_with_config(
  config: chrome.BrowserConfig,
) -> Result(Subject(chrome.Message), chrome.LaunchError) {
  validate_launch(chrome.launch_with_config(config))
}

/// Launch a browser, and read the configuration from environment variables.
/// The browser path variable must be set, all others will fall back to a default.
/// 
/// This function will validate that the browser launched successfully, and the 
/// protocol version matches the one supported by this library.
/// 
/// Configuration variables:
/// - `CHROBOT_BROWSER_PATH` - The path to the browser executable
/// - `CHROBOT_BROWSER_ARGS` - The arguments to pass to the browser, separated by spaces
/// - `CHROBOT_BROWSER_TIMEOUT` - The timeout in milliseconds to wait for the browser to start, must be an integer
/// - `CHROBOT_LOG_LEVEL` - The log level to use, one of `silent`, `warnings`, `info`, `debug`
/// 
pub fn launch_with_env() -> Result(Subject(chrome.Message), chrome.LaunchError) {
  validate_launch(chrome.launch_with_env())
}

/// Open a new page in the browser.
/// Returns a response when the protocol call succeeds, please use
/// [`await_selector`](#await_selector) to determine when the page is ready.  
/// The timeout passed to this function will be attached to the returned
/// [`Page`](#Page) type to be reused by other functions in this module.  
/// You can always adjust it using [`with_timeout`](#with_timeout).
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

  // Return the page
  Ok(Page(
    browser: browser_subject,
    session_id: session_response.session_id,
    target_id: target_response.target_id,
    time_out: time_out,
  ))
}

/// Close the passed page
pub fn close(page: Page) -> Result(dynamic.Dynamic, RequestError) {
  target.close_target(page_caller(page), page.target_id)
}

/// Similar to [`open`](#open), but creates a new page from HTML that you pass to it.
/// The page will be created under the `about:blank` URL.
pub fn create_page(
  with browser: Subject(chrome.Message),
  from html: String,
  time_out time_out: Int,
) {
  use created_page <- result.try(open(browser, "about:blank", time_out))
  use _ <- result.try(await_selector(created_page, "body"))

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
/// The Ok(result) of this function can be passed to [`to_file`](#to_file)  
///   
/// If you want to customize the settings of the output image, use [`page.capture_screenshot`](/chrobot/protocol/page.html#capture_screenshot) directly.
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
/// If you want to customize the settings of the output document, use [`page.print_to_pdf`](/chrobot/protocol/page.html#print_to_pdf) directly.
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

/// Write a file returned from [`screenshot`](#screenshot) or [`pdf`](#pdf) to a file.  
/// File path should not include the file extension, it will be appended automatically!  
/// Will return a FileError from the `simplifile` package if not successfull
pub fn to_file(
  input input: EncodedFile,
  path path: String,
) -> Result(Nil, file.FileError) {
  let res =
    bit_array.base64_decode(input.data)
    |> result.replace_error(file.Unknown("Could not decode base64 string"))

  use binary <- result.try(res)
  file.write_bits(to: path <> "." <> input.extension, bits: binary)
}

/// Evaluate some JavaScript on the page and return the result,
/// which will be a [`runtime.RemoteObject`](/chrobot/protocol/runtime.html#RemoteObject) reference.  
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

pub fn eval_to_value(on page: Page, js expression: String) {
  runtime.evaluate(
    page_caller(page),
    expression: expression,
    object_group: None,
    include_command_line_api: None,
    silent: Some(False),
    // will be the current page by default
    context_id: None,
    return_by_value: Some(True),
    user_gesture: Some(True),
    await_promise: Some(False),
  )
  |> handle_eval_response()
}

/// Like [`eval`](#eval), but awaits for the result of the evaluation
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

/// Evalute a [`runtime.RemoteObjectId`](/chrobot/protocol/runtime.html#RemoteObjectId) to a value,
/// passing in the appropriate decoder function
pub fn to_value(
  on page: Page,
  from remote_object_id: runtime.RemoteObjectId,
  to decoder,
) {
  let declaration =
    "function to_value(){
    return JSON.stringify(this)
  }"

  call_custom_function_on(
    page_caller(page),
    declaration,
    remote_object_id,
    [],
    decoder,
  )
}

/// Cast a RemoteObject into a value by passing a dynamic decoder.  
/// This is a convenience for when you know a RemoteObject is returned by value and not ID,
/// and you want to extract the value from it.  
/// Because it accepts a Result, you can chain this to [`eval`](#eval) or [`eval_async`](#eval_async) like so:
/// ```gleam
/// eval(page, "window.document.documentElement.outerHTML")
///   |> as_value(dynamic.string)
/// ```
pub fn as_value(
  result: Result(runtime.RemoteObject, chrome.RequestError),
  decoder,
) {
  case result {
    Ok(runtime.RemoteObject(_, _, _, Some(value), _, _, _)) -> {
      decoder(value)
      |> result.replace_error(chrome.ProtocolError)
    }
    Error(something) -> Error(something)
    _ -> Error(chrome.NotFoundError)
  }
}

/// Assuming the passed [`runtime.RemoteObjectId`](/chrobot/protocol/runtime.html#RemoteObjectId) reference is an Element,
/// return an attribute of that element.  
/// Attributes are always returned as a string.  
/// If the attribute is not found, or the item is not an Element, an error will be returned.  
/// 
/// ## Example
/// ```gleam
/// let assert Ok(foo_data) = get_attribute(page, item, "data-foo")
/// ```
pub fn get_attribute(
  on page: Page,
  from item: runtime.RemoteObjectId,
  name attribute_name: String,
) {
  let declaration =
    "function get_arg(attribute_name)
  {
    return this.getAttribute(attribute_name)
  }
"
  call_custom_function_on(
    page_caller(page),
    declaration,
    item,
    [StringArg(attribute_name)],
    dynamic.string,
  )
}

/// Convencience function to simulate a click on an element by selector.  
/// See [`click`](#click) for more info.
pub fn click_selector(on page: Page, target selector: String) {
  use item <- result.try(select(page, selector))
  click(page, item)
}

/// Simulate a click on an element.  
/// Calls [`HTMLElement.click()`](https://developer.mozilla.org/en-US/docs/Web/API/HTMLElement/click) via JavaScript.
pub fn click(on page: Page, target item: runtime.RemoteObjectId) {
  let declaration =
    "function click_el(){
    return this.click()
  }"
  call_custom_function_on_raw(page_caller(page), declaration, item, [])
  |> result.replace(Nil)
}

/// Convenience function to focus an element by selector.  
/// See [`focus`](#focus) for more info.  
pub fn focus_selector(on page: Page, target selector: String) {
  use item <- result.try(select(page, selector))
  focus(page, item)
}

/// Focus an element.  
/// Calls [`HTMLElement.focus()`](https://developer.mozilla.org/en-US/docs/Web/API/HTMLElement/focus) via JavaScript.
pub fn focus(on page: Page, target item: runtime.RemoteObjectId) {
  let declaration =
    "function focus_el(){
    return this.focus()
  }"
  call_custom_function_on_raw(page_caller(page), declaration, item, [])
  |> result.replace(Nil)
}

/// Simulate a keydown event for a given key.  
/// 
/// You can pass in latin characters, digits and some DOM key names,
/// The keymap is based on the US keyboard layout.  
/// 
/// [⌨️ You can see the supported key values here](https://github.com/JonasGruenwald/chrobot/blob/main/src/chrobot/internal/keymap.gleam)
pub fn down_key(on page: Page, key key: String, modifiers modifiers: Int) {
  let key_data_result = keymap.get_key_data(key)
  case key_data_result {
    Ok(key_data) -> {
      let text = {
        case key_data.text {
          Some(text) -> Some(text)
          None -> Some(key)
        }
      }
      input.dispatch_key_event(
        page_caller(page),
        type_: {
          case text {
            Some(_text) -> input.DispatchKeyEventTypeKeyDown
            None -> input.DispatchKeyEventTypeRawKeyDown
          }
        },
        modifiers: Some(modifiers),
        timestamp: None,
        text: text,
        unmodified_text: text,
        key_identifier: None,
        code: key_data.code,
        key: key_data.key,
        windows_virtual_key_code: key_data.key_code,
        native_virtual_key_code: None,
        auto_repeat: None,
        is_keypad: {
          case key_data.location {
            Some(3) -> Some(True)
            _ -> None
          }
        },
        is_system_key: None,
        location: key_data.location,
      )
      |> result.replace(Nil)
    }
    Error(Nil) -> {
      utils.warn("You are attempting to trigger a key which is not supported
by the chrobot virtual keyboard.
The key to be pressed down is: '" <> key <> "'.
Chrobot simulates a US keyboard layout,
it's best to stick to ASCII characters and DOM key names!")
      Error(chrome.NotFoundError)
    }
  }
}

/// Simulate a keyup event for a given key.  
/// 
/// You can pass in latin characters, digits and some DOM key names,
/// The keymap is based on the US keyboard layout.  
/// 
/// [⌨️ You can see the supported key values here](https://github.com/JonasGruenwald/chrobot/blob/main/src/chrobot/internal/keymap.gleam)
pub fn up_key(on page: Page, key key: String, modifiers modifiers: Int) {
  let key_data_result = keymap.get_key_data(key)
  case key_data_result {
    Ok(key_data) -> {
      input.dispatch_key_event(
        page_caller(page),
        type_: input.DispatchKeyEventTypeKeyUp,
        modifiers: Some(modifiers),
        timestamp: None,
        text: key_data.text,
        unmodified_text: key_data.text,
        key_identifier: None,
        code: key_data.code,
        key: key_data.key,
        windows_virtual_key_code: key_data.key_code,
        native_virtual_key_code: None,
        auto_repeat: None,
        is_keypad: {
          case key_data.location {
            Some(3) -> Some(True)
            _ -> None
          }
        },
        is_system_key: None,
        location: key_data.location,
      )
      |> result.replace(Nil)
    }
    Error(Nil) -> {
      utils.warn("You are attempting to trigger a key which is not supported
by the chrobot virtual keyboard.
The key to be released is: '" <> key <> "'.
Chrobot simulates a US keyboard layout,
it's best to stick to ASCII characters and DOM key names!")
      Error(chrome.NotFoundError)
    }
  }
}

/// Simulate a keypress for a given key.  
/// This will trigger a keydown and keyup event in sequence.  
/// 
/// You can pass in latin characters, digits and some DOM key names,
/// The keymap is based on the US keyboard layout.  
/// 
/// [⌨️ You can see the supported key values here](https://github.com/JonasGruenwald/chrobot/blob/main/src/chrobot/internal/keymap.gleam)
/// 
/// If you want to insert a whole string into an input field, use `type_text` instead.
pub fn press_key(on page: Page, key key: String) {
  use _ <- result.try(down_key(page, key, 0))
  up_key(page, key, 0)
}

/// Insert the given character into a [focus](#focus)ed input field by sending a `char` keyboard event.  
/// Note that this does not trigger a keydown or keyup event, see [`press_key`](#press_key) for that.  
/// If you want to insert a whole string into an input field, use [`type_text`](#type_text) instead.  
pub fn insert_char(on page: Page, key key: String) {
  input.dispatch_key_event(
    page_caller(page),
    type_: input.DispatchKeyEventTypeChar,
    modifiers: None,
    timestamp: None,
    text: Some(key),
    unmodified_text: None,
    key_identifier: None,
    code: None,
    key: None,
    windows_virtual_key_code: None,
    native_virtual_key_code: None,
    auto_repeat: None,
    is_keypad: None,
    is_system_key: None,
    location: None,
  )
  |> result.replace(Nil)
}

/// Type text by simulating keypresses for each character in the input string.  
/// Note: If a character is not supported by the virtual keyboard, it will be inserted using a char event,
/// which will not produce keydown or keyup events.  
/// [⌨️ You can see the key values supported by the virtual keyboard here](https://github.com/JonasGruenwald/chrobot/blob/main/src/chrobot/internal/keymap.gleam)  
/// 
/// If you want to type text into an input field, make sure to [`focus`](#focus) it first!  
pub fn type_text(on page, text input: String) {
  string.to_graphemes(input)
  |> list.map(fn(char) {
    case keymap.get_key_data(char) {
      Ok(_) -> press_key(page, char)
      Error(_) -> insert_char(page, char)
    }
  })
  |> result.all()
  |> result.replace(Nil)
}

/// Get a property of a [`runtime.RemoteObjectId`](/chrobot/protocol/runtime.html#RemoteObjectId) and decode it with the provided decoder  
/// 
/// ## Example
/// ```gleam
/// import gleam/dynamic
/// let assert Ok(link_target) = get_property(page, item, "href", dynamic.string)
/// ```
pub fn get_property(
  on page: Page,
  from item: runtime.RemoteObjectId,
  name property_name: String,
  property_decoder property_decoder,
) {
  let declaration =
    "function get_prop(property_name)
  {
    return this[property_name]
  }
"
  call_custom_function_on(
    page_caller(page),
    declaration,
    item,
    [StringArg(property_name)],
    property_decoder,
  )
}

/// Get the text content of an element.  
/// Returns the [`HTMLElement.innerText`](https://developer.mozilla.org/en-US/docs/Web/API/HTMLElement/innerText) property via JavaScript, NOT `Node.textContent`.  
/// Learn about the differences [here](https://developer.mozilla.org/en-US/docs/Web/API/Node/textContent#differences_from_innertext).
pub fn get_text(on page: Page, from item: runtime.RemoteObjectId) {
  get_property(page, item, "innerText", dynamic.string)
}

/// Get the inner HTML of an element.
/// Returns the [`Element.innerHTML`](https://developer.mozilla.org/en-US/docs/Web/API/Element/innerHTML) JavaScript property.
pub fn get_inner_html(on page: Page, from item: runtime.RemoteObjectId) {
  get_property(page, item, "innerHTML", dynamic.string)
}

/// Get the outer HTML of an element.  
/// Returns the [`Element.outerHTML`](https://developer.mozilla.org/en-US/docs/Web/API/Element/outerHTML) JavaScript property.
pub fn get_outer_html(on page: Page, from item: runtime.RemoteObjectId) {
  get_property(page, item, "outerHTML", dynamic.string)
}

/// Return the entire HTML of the page as a string.  
/// Returns `document.documentElement.outerHTML` via JavaScript.
pub fn get_all_html(on page: Page) {
  eval(page, "window.document.documentElement.outerHTML")
  |> as_value(dynamic.string)
}

/// Run [`document.querySelector`](https://developer.mozilla.org/en-US/docs/Web/API/Document/querySelector) on the page
/// and return a single [`runtime.RemoteObjectId`](/chrobot/protocol/runtime.html#RemoteObjectId)
/// for the first matching element.
pub fn select(on page: Page, matching selector: String) {
  let selector_code = "window.document.querySelector(\"" <> selector <> "\")"
  eval(page, selector_code)
  |> handle_object_id_response()
}

/// Run [`document.querySelectorAll`](https://developer.mozilla.org/en-US/docs/Web/API/Document/querySelectorAll) on the page and return a list of [`runtime.RemoteObjectId`](/chrobot/protocol/runtime.html#RemoteObjectId) items 
/// for all matching elements.
pub fn select_all(on page: Page, matching selector: String) {
  let selector_code = "window.document.querySelectorAll(\"" <> selector <> "\")"
  let result = eval(page, selector_code)
  case result {
    Ok(runtime.RemoteObject(_, _, _, _, _, _, Some(remote_object_id))) -> {
      use result_properties <- result.try(runtime.get_properties(
        page_caller(page),
        remote_object_id,
        own_properties: Some(True),
      ))

      case result_properties {
        runtime.GetPropertiesResponse(
          result: _,
          internal_properties: _,
          exception_details: Some(exception),
        ) -> {
          Error(chrome.RuntimeException(
            text: exception.text,
            line: exception.line_number,
            column: exception.column_number,
          ))
        }
        runtime.GetPropertiesResponse(
          result: property_descriptors,
          internal_properties: _internal_props,
          exception_details: None,
        ) -> {
          Ok(
            list.filter_map(property_descriptors, fn(prop_descriptor) {
              case prop_descriptor {
                runtime.PropertyDescriptor(
                  _,
                  Some(runtime.RemoteObject(_, _, _, _, _, _, Some(object_id))),
                  _,
                  _,
                  _,
                  _,
                  _,
                  _,
                  _,
                  _,
                ) -> {
                  Ok(object_id)
                }
                _ -> Error(Nil)
              }
            }),
          )
        }
      }
    }
    Ok(_) -> {
      Ok([])
    }
    Error(any) -> Error(any)
  }
}

/// Continously attempt to run a selector, until it succeeds.  
/// You can use this after opening a page, to wait for the moment it has initialized
/// enough sufficiently for you to run your automation on it.  
/// The final result will be single [`runtime.RemoteObjectId`](/chrobot/protocol/runtime.html#RemoteObjectId)
pub fn await_selector(
  on page: Page,
  select selector: String,
) -> Result(runtime.RemoteObjectId, RequestError) {
  // 🦜
  let polly = fn() {
    eval(page, "window.document.querySelector(\"" <> selector <> "\")")
    |> handle_object_id_response()
  }

  poll(polly, page.time_out)
}

/// Block until the page load event has fired.
/// Note that with local pages, the load event can often fire 
/// before the handler is attached.  
/// It's best to use [`await_selector`](#await_selector) instead of this
pub fn await_load_event(browser, page: Page) {
  // Enable Page domain to receive events like ` Page.loadEventFired`
  use _ <- result.try(page.enable(page_caller(page)))

  // // Wait for the load event to fire
  chrome.listen_once(browser, "Page.loadEventFired", page.time_out)
}

/// Quit the browser (alias for [`chrome.quit`](/chrobot/chrome.html#quit))
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
const poll_delay = 5

/// Utility to repeatedly call a browser function until it succeeds or times out.
pub fn poll(
  callback: fn() -> Result(a, chrome.RequestError),
  timeout: Int,
) -> Result(a, chrome.RequestError) {
  let deadline = utils.get_time_ms() + timeout
  do_poll(callback, deadline, None)
}

fn do_poll(
  callback: fn() -> Result(a, chrome.RequestError),
  deadline: Int,
  previous_error: Option(chrome.RequestError),
) -> Result(a, chrome.RequestError) {
  // available time before current polling attempt
  let available_time = deadline - utils.get_time_ms()

  // We guard against negative time because it would cause a panic in try_await
  // but realistically this should never happen anyways
  use <- bool.guard(available_time < 0, Error(chrome.ChromeAgentTimeout))

  let result =
    callback
    |> task.async()
    |> task.try_await(available_time)

  // remaining available time after the polling attempt finishes
  let available_time = deadline - utils.get_time_ms() - poll_delay

  case result {
    // Task did not return before deadline
    // A task exit should never happen but we consider it a timeout
    Error(task.Timeout) | Error(task.Exit(_)) -> {
      // We return the error from the last failed poll attempt if there was one
      case previous_error {
        Some(err) -> Error(err)
        None -> Error(chrome.ChromeAgentTimeout)
      }
    }
    // Task returned Ok result, polling is done 
    // and result is returned
    Ok(Ok(res)) -> Ok(res)
    // Task returned an error and we still have time, we continue polling with delay
    Ok(Error(err)) if available_time > 0 -> {
      process.sleep(poll_delay)
      do_poll(callback, deadline, Some(err))
    }
    // Task returned an error but the time is up
    Ok(Error(err)) -> {
      Error(err)
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
/// This is useful when you want to make raw protocol calls  
/// 
/// ## Example
/// ```gleam
/// import chrobot.{open, page_caller}
/// import gleam/option.{None}
/// import protocol/page
/// pub fn main() {
///   let assert Ok(browser) = chrobot.launch()
///   let assert Ok(page) = open(browser, "https://example.com", 5000)
///   let callback = page_caller(page)
///   let assert Ok(_) =
///     page.navigate(callback, "https://gleam.run", None, None, None)
/// }
/// ```
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

fn handle_object_id_response(response) {
  case response {
    Ok(runtime.RemoteObject(_, _, _, _, _, _, Some(remote_object_id))) -> {
      Ok(remote_object_id)
    }
    Ok(_) -> {
      Error(chrome.NotFoundError)
    }
    Error(any) -> Error(any)
  }
}

/// Type wrapper to let you pass in custom arguments of different types 
/// to a JavaScript function as a list of the same type
pub type CallArgument {
  StringArg(value: String)
  IntArg(value: Int)
  FloatArg(value: Float)
  BoolArg(value: Bool)
  ArrayArg(value: List(CallArgument))
}

fn encode_custom_arg(arg: CallArgument) {
  case arg {
    StringArg(value) -> json.string(value)
    IntArg(value) -> json.int(value)
    FloatArg(value) -> json.float(value)
    BoolArg(value) -> json.bool(value)
    ArrayArg(value) -> json.array(value, encode_custom_arg)
  }
}

fn encode_custom_arguments(input: List(CallArgument)) {
  json.array(input, fn(arg) {
    json.object([#("value", encode_custom_arg(arg))])
  })
}

// }
/// This is a version of [`runtime.call_function_on`](/chrobot/protocol/runtime.html#call_function_on) which allows
/// passing in arguments, and always returns the result as a value,
/// which will be decoded by the decoder you pass in
///  
/// You would use it with a JavaScript function declaration like this:  
/// ```js
/// function my_function(my_arg) {
///   // You can access the passed RemoteObject with `this`
///   const wibble = this.getAttribute('href')
///   // You have access to the arguments you passed in
///   const wobble = 'hello ' + my_arg
///   // You receive this return value, you should pass in a string decoder
///   // in this case
///   return wibble + wobble;
/// }
/// ```
pub fn call_custom_function_on(
  callback,
  function_declaration function_declaration: String,
  object_id object_id: runtime.RemoteObjectId,
  args arguments: List(CallArgument),
  value_decoder value_decoder,
) {
  // Make call
  let encoded_arguments = encode_custom_arguments(arguments)
  let payload =
    Some(
      json.object([
        #("functionDeclaration", json.string(function_declaration)),
        #("objectId", runtime.encode__remote_object_id(object_id)),
        #("arguments", encoded_arguments),
        #("returnByValue", json.bool(True)),
      ]),
    )

  // Parse response
  use result <- result.try(callback("Runtime.callFunctionOn", payload))
  use decoded_response <- result.try(
    runtime.decode__call_function_on_response(result)
    |> result.replace_error(chrome.ProtocolError),
  )

  // Ensure response contains a value
  case decoded_response {
    runtime.CallFunctionOnResponse(_, Some(exception)) -> {
      Error(chrome.RuntimeException(
        text: exception.text,
        line: exception.line_number,
        column: exception.column_number,
      ))
    }
    runtime.CallFunctionOnResponse(
      runtime.RemoteObject(_, _, _, Some(value), _, _, _),
      None,
    ) -> {
      value_decoder(value)
      |> result.replace_error(chrome.ProtocolError)
    }
    _ -> Error(chrome.NotFoundError)
  }
}

/// This is a version of `call_custom_function_on` which does not attempt
/// to decode the result as a value and just returns it directly instead.  
/// Useful when the return value should be discarded or handled in a custom way.
pub fn call_custom_function_on_raw(
  callback,
  function_declaration function_declaration: String,
  object_id object_id: runtime.RemoteObjectId,
  args arguments: List(CallArgument),
) {
  // Make call
  let encoded_arguments = encode_custom_arguments(arguments)
  let payload =
    Some(
      json.object([
        #("functionDeclaration", json.string(function_declaration)),
        #("objectId", runtime.encode__remote_object_id(object_id)),
        #("arguments", encoded_arguments),
        #("returnByValue", json.bool(True)),
      ]),
    )
  // Parse response
  use result <- result.try(callback("Runtime.callFunctionOn", payload))
  use decoded_response <- result.try(
    runtime.decode__call_function_on_response(result)
    |> result.replace_error(chrome.ProtocolError),
  )

  // Ensure response contains a value
  case decoded_response {
    runtime.CallFunctionOnResponse(_, Some(exception)) -> {
      Error(chrome.RuntimeException(
        text: exception.text,
        line: exception.line_number,
        column: exception.column_number,
      ))
    }
    _ -> Ok(decoded_response)
  }
}
