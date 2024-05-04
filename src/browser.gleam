//// An actor that manages an instance of the chrome browser.
//// The browser is started to allow remote debugging via a websocket connection.
//// 
//// In the future I would prefer to have communication done directly via pipes,
//// but I can't figure out how to do that in gleam at the moment.
//// 

import gleam/dynamic as d
import gleam/erlang/atom
import gleam/erlang/os
import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import glexec.{type OsPid} as exec
import simplifile as file

pub type LaunchError {
  UnknowOperatingSystem
  CouldNotFindExecutable
  FailedToStart
}

pub type BrowserConfig {
  BrowserConfig(path: String, args: List(String), start_timeout: Int)
}

pub type BrowserInstance {
  BrowserInstance(exec_pid: process.Pid, os_pid: exec.OsPid)
}

/// Get the default arguments the browser should be started with
pub fn get_default_chrome_args() {
  [
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
    "--disable-renderer-backgrounding", "--disable-sync", "--enable-automation",
    "--enable-features=NetworkServiceInProcess2", "--export-tagged-pdf",
    "--force-color-profile=srgb", "--hide-scrollbars",
    "--metrics-recording-only", "--no-default-browser-check", "--no-first-run",
    "--no-service-autorun", "--password-store=basic", "--use-mock-keychain",
  ]
}

pub fn get_first_existing_path(
  paths: List(String),
) -> Result(String, LaunchError) {
  let existing_paths =
    paths
    |> list.filter(fn(current) {
      case file.verify_is_file(current) {
        Ok(res) -> res
        Error(_) -> False
      }
    })

  case existing_paths {
    [first, ..] -> Ok(first)
    [] -> Error(CouldNotFindExecutable)
  }
}

/// Try to find a chrome executable in some obvious places
/// (It should be preferred to set the path explicitly if possible)
pub fn get_default_chrome_path() {
  case os.family() {
    os.Darwin ->
      get_first_existing_path([
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary",
      ])
    os.Linux ->
      get_first_existing_path([
        "/usr/bin/google-chrome", "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
      ])
    os.WindowsNt ->
      get_first_existing_path([
        "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
        "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
        "C:\\Program Files\\Chromium\\Application\\chrome.exe",
        "C:\\Program Files (x86)\\Chromium\\Application\\chrome.exe",
      ])
    _ -> Error(UnknowOperatingSystem)
  }
}

pub type Message {
  Stop
  BrowserDown
}

fn create_init_fn(cfg: BrowserConfig) {
  fn() {
    io.println("Starting browser with path: " <> cfg.path)
    let command_list =
      [cfg.path, "--remote-debugging-port=0", ..cfg.args]
      |> list.append(["2>/dev/null 3<&0 4>&1"])

    io.println("Command: " <> string.join(command_list, " "))
    let res =
      exec.new()
      |> exec.with_stdout(exec.StdoutPid(process.self()))
      |> exec.with_stderr(exec.StderrPid(process.self()))
      |> exec.with_stdin(exec.StdinPipe)
      |> exec.with_monitor(True)
      |> exec.with_verbose(True)
      |> exec.run_async(exec.Execve(command_list))

    case res {
      Ok(exec.Pids(glexec_pid, os_pid)) -> {
        let instance = BrowserInstance(glexec_pid, os_pid)
        log(instance, "Started")
        actor.Ready(
          instance,
          process.new_selector()
            |> process.selecting_record5(
            atom.create_from_string("DOWN"),
            handle_browser_down,
          ),
        )
      }
      Error(err) -> {
        io.debug(#("Browser start error: ", err))
        actor.Failed("Browser did not start")
      }
    }
  }
}

fn handle_browser_down(
  param_os_pid: d.Dynamic,
  param_process: d.Dynamic,
  param_pid: d.Dynamic,
  param_reason: d.Dynamic,
) {
  // TODO check exit reason and return different messages based on it
  BrowserDown
}

fn loop(message: Message, state: BrowserInstance) {
  case message {
    Stop -> {
      log(state, "Stopping on request")
      let _ = exec.stop(state.os_pid)
      actor.Stop(process.Normal)
    }
    BrowserDown -> {
      log(state, "Stopping because browser exited")
      actor.Stop(process.Normal)
    }
  }
}

pub fn launch_with_config(cfg: BrowserConfig) {
  actor.start_spec(actor.Spec(
    init: create_init_fn(cfg),
    loop: loop,
    init_timeout: cfg.start_timeout,
  ))
}

pub fn launch() {
  use chrome_path <- result.try(get_default_chrome_path())
  io.println("Resolved chrome path: " <> chrome_path)

  launch_with_config(BrowserConfig(
    path: chrome_path,
    args: get_default_chrome_args(),
    start_timeout: 10_000,
  ))
  |> result.replace_error(FailedToStart)
}

fn log(instance: BrowserInstance, message: String) {
  io.println("[Browser:" <> int.to_string(instance.os_pid) <> "] " <> message)
}
