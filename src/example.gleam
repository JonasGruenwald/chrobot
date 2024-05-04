import browser
import gleam/erlang/process
import gleam/io

pub fn main() {
  let config =
    browser.BrowserConfig(
      path: "/Users/jonas/Projects/chrobot/chrome/mac_arm-126.0.6457.0/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
      args: [
        "--headless", "--disable-accelerated-2d-canvas", "--disable-gpu",
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
      start_timeout: 5000,
    )
  let assert Ok(browser_subject) = browser.launch()
  // let assert Ok(browser_subject) = browser.launch_with_config(config)

  io.debug(#("browser_subject: ", browser_subject))
  process.sleep_forever()
}
