//
//  Run this example with `gleam run -m chrobot/examples/raw_protocol_calls`
// 

import chrobot
import chrome
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import protocol/dom

pub fn main() {
  let assert Ok(chrome_path) = chrome.get_local_chrome_path()
  let assert Ok(browser) =
    chrobot.launch_with_config(chrome.BrowserConfig(
      args: [
        "--disable-accelerated-2d-canvas", "--disable-gpu",
        "--allow-pre-commit-input", "--disable-background-networking",
        "--disable-background-timer-throttling",
        "--disable-backgrounding-occluded-windows", "--disable-breakpad",
        "--disable-client-side-phishing-detection",
        "--disable-component-extensions-with-background-pages",
        "--disable-component-update", "--disable-default-apps",
        "--disable-extensions",
        "--disable-features=Translate,BackForwardCache,AcceptCHFrame,MediaRouter,OptimizationHints",
        "--disable-hang-monitor", "--disable-ipc-flooding-protection",
        "--disable-popup-blocking", "--disable-prompt-on-repost",
        "--disable-renderer-backgrounding", "--disable-sync",
        "--enable-automation", "--enable-features=NetworkServiceInProcess2",
        "--export-tagged-pdf", "--force-color-profile=srgb", "--hide-scrollbars",
        "--metrics-recording-only", "--no-default-browser-check",
        "--no-first-run", "--no-service-autorun", "--password-store=basic",
        "--use-mock-keychain",
      ],
      path: chrome_path,
      start_timeout: 1000,
    ))
  io.println("Browser has been launched")
  let assert Ok(page) =
    browser
    |> chrobot.open("http://example.com", 10_000)

  io.println("Page has been opened")
  process.sleep(1000)

  let page_caller = chrobot.page_caller(page)
  let assert Ok(outer_res) =
    dom.get_outer_html(page_caller, Some(page.root_node.node_id), None, None)
  io.debug(#("outer", outer_res))

  let assert Ok(element) = chrobot.select(page, "body")
  io.println("Element has been selected")
  io.debug(element)

  let assert Ok(_) = chrobot.quit(browser)
}
