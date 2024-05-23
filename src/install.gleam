/// This module provides basic browser installation functionality, allowing you
/// to install a local version of [Google Chrome for Testing](https://github.com/GoogleChromeLabs/chrome-for-testing) in the current directory.
///  
/// You may run browser installation directly with `gleam run -m chrobot/install`.
/// When running directly, you can configure the browser version to install by setting the `CHROBOT_TARGET_VERSION` environment variable,
/// it will default to `latest`, you may also set the directory to install under, with `CHROBOT_TARGET_PATH`.
/// 
/// The browser will be installed into a directory called `chrome` under the target directory.
/// There is no support for managing multiple browser installations, if an installation is already present, 
/// the script will overwrite it, if it is the same version.
/// 
/// To uninstall browsers installed by this tool just remove the `chrome` directory created by it, or delete an individual browser
/// installation from inside it.
/// 
/// This module attempts to rudimentarily mimic the functionality of the [puppeteer install script](https://pptr.dev/browsers-api),
/// the only goal is to have a quick and convenient way to install browsers locally, for more advanced management of browser
/// installations, please seek out other tools.
/// 
/// Installation source is Google's official Chrome for Testing distrubtion:
/// https://github.com/GoogleChromeLabs/chrome-for-testing
/// 
/// Supported platforms are bound by what that distribution supports, which is currently:
/// 
/// * linux64
/// * mac-arm64
/// * mac-x64
/// * win32
/// * win64
/// 
/// Notably, this distribution **unfortunately does not support ARM64 on Linux**.
/// 
import chrobot/internal/utils
import chrome
import filepath as path
import gleam/erlang/os
import gleam/erlang/process
import gleam/io
import gleam/result

pub fn main() {
  install()
}

pub fn install() {
  let target_version =
    result.unwrap(os.get_env("CHROBOT_TARGET_VERSION"), "latest")
  let target_path = result.unwrap(os.get_env("CHROBOT_TARGET_PATH"), ".")
  install_with_config(target_path, target_version)
}

pub fn install_with_config(target_path: String, target_version: String) {
  let chrome_dir_path = path.join(target_path, "chrome")
  let chrome_dir_path = case chrome_dir_path {
    "./chrome" -> "chrome"
    other -> other
  }
  io.println(
    "\nPreparing to install Chrome for Testing ("
    <> target_version
    <> ") into "
    <> chrome_dir_path
    <> ".\n",
  )

  // Existing version sanity check
  case chrome.get_local_chrome_path_at(chrome_dir_path) {
    Ok(local_chrome_path) -> {
      utils.warn(
        "You already have a local Chrome installation at this path:\n"
        <> local_chrome_path
        <> "
It will be overwritten if it is the same version as the one to be installed.
Chrobot does not support managing multiple browser installations, 
you are encouraged to remove old installations manually if you no longer need them.",
      )
    }
    Error(_) -> {
      { io.println("Downloading Chrome for Testing...") }
    }
  }

  let assert Ok(platform) = resolve_platform()
  todo
}

fn resolve_platform() -> Result(String, String) {
  case os.family(), get_arch() {
    os.Darwin, "aarch64" <> _ -> {
      Ok("mac-arm64")
    }
    os.Darwin, _ -> {
      Ok("mac-x64")
    }
    os.Linux, "x86_64" -> {
      utils.warn(
        "You appear to be on linux, just to let you know, dependencies are not installed automatically by this script,
you must install them yourself! You may check `ldd chrome | grep not` to see what dependencies are missing.
See also: https://github.com/puppeteer/puppeteer/blob/main/docs/troubleshooting.md#chrome-doesnt-launch-on-linux",
      )
      Ok("linux64")
    }
    os.WindowsNt, "x86_64" -> {
      Ok("win64")
    }
    os.WindowsNt, _ -> {
      Ok("win32")
    }
    _, architecture -> {
      utils.err(
        "Could not resolve an appropriate platform for your system. 
Please note that the available platforms are limited by what Google Chrome for Testing supports,
notably, ARM64 on Linux is unfortunately not supported at the moment.",
      )
      Error("Unsupported system: " <> architecture)
    }
  }
}

@external(erlang, "chrobot_ffi", "get_arch")
fn get_arch() -> String
