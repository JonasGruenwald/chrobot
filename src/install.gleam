//// This module provides basic browser installation functionality, allowing you
//// to install a local version of [Google Chrome for Testing](https://github.com/GoogleChromeLabs/chrome-for-testing) in the current directory.
////  
//// You may run browser installation directly with 
//// 
//// ```sh
//// gleam run -m chrobot/install
//// ```
//// When running directly, you can configure the browser version to install by setting the `CHROBOT_TARGET_VERSION` environment variable,
//// it will default to `latest`. 
//// You may also set the directory to install under, with `CHROBOT_TARGET_PATH`.
//// 
//// The browser will be installed into a directory called `chrome` under the target directory.
//// There is no support for managing multiple browser installations, if an installation is already present for the same version,
//// the script will overwrite it.
//// 
//// To uninstall browsers installed by this tool just remove the `chrome` directory created by it, or delete an individual browser
//// installation from inside it.
//// 
//// This module attempts to rudimentarily mimic the functionality of the [puppeteer install script](https://pptr.dev/browsers-api),
//// the only goal is to have a quick and convenient way to install browsers locally, for more advanced management of browser
//// installations, please seek out other tools.
//// 
//// Supported platforms are limited by what the Google Chrome for Testing distribution supports, which is currently:
//// 
//// * linux64
//// * mac-arm64
//// * mac-x64
//// * win32
//// * win64
//// 
//// Notably, this distribution **unfortunately does not support ARM64 on Linux**.
//// 

import chrobot/internal/utils
import chrome
import filepath as path
import gleam/bool
import gleam/dynamic
import gleam/erlang/os
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import simplifile as file

const version_list_endpoint = "https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json"

pub type InstallationError {
  InstallationError
}

pub fn main() {
  install()
}

/// Install a local version of Google Chrome for Testing.
/// This function is meant to be called in a script, it will log errors and warnings to the console.
/// and return a generic error if installation fails.
pub fn install() {
  let target_version =
    result.unwrap(os.get_env("CHROBOT_TARGET_VERSION"), "latest")
  let target_path = result.unwrap(os.get_env("CHROBOT_TARGET_PATH"), ".")
  install_with_config(target_path, target_version)
}

/// Install a specific local version of Google Chrome for Testing to a specific directory.
/// This function is meant to be called in a script, it will log errors and warnings to the console.
/// and return a generic error if installation fails.
pub fn install_with_config(
  to target_path: String,
  version target_version: String,
) {
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
    Error(_) -> Nil
  }

  use platform <- assert_ok(resolve_platform(), "Platform unsupported")
  let p = utils.start_progress("Fetching available versions...")
  use req <- assert_ok(
    request.to(version_list_endpoint),
    "Failed to build version request",
  )
  use res <- assert_ok(
    httpc.send(req),
    "Version list request failed, ensure you have an active internet connection.",
  )
  use <- assert_true(
    res.status == 200,
    "Version list request returned a non-200 status code.",
  )

  use <- assert_is_json(
    res,
    "Version list request returned a response that is not JSON.",
  )

  use payload <- assert_ok(
    json.decode(res.body, dynamic.dynamic),
    "Failed to parse version list JSON",
  )

  use version_list <- assert_ok(
    parse_version_list(payload),
    "Failed to decode version list JSON - Maybe the API has changed or is down?",
  )

  use version <- assert_ok(
    select_version(target_version, version_list),
    "Failed to find version " <> target_version <> " in version list",
  )

  use download <- assert_ok(
    select_download(version, platform),
    "Failed to find download for platform "
      <> platform
      <> " in version "
      <> version.version,
  )

  utils.stop_progress(p)

  io.println(
    "\nSelected version "
    <> version.version
    <> " for platform "
    <> download.platform
    <> "\n",
  )

  let p = utils.start_progress("Downloading Chrome for Testing...")

  use download_request <- assert_ok(
    new_download_request(download.url),
    "Failed to build download request",
  )
  use download_res <- assert_ok(
    httpc.send_bits(download_request),
    "Download request failed, ensure you have an active internet connection",
  )
  use <- assert_true(
    download_res.status == 200,
    "Download request returned a non-200 status code",
  )

  utils.set_progress(p, "Writing download to disk...")

  let download_path =
    path.join(
      chrome_dir_path,
      "chrome_download_" <> download.platform <> version.revision <> ".zip",
    )

  let installation_dir =
    path.join(chrome_dir_path, platform <> "-" <> version.version)

  use _ <- assert_ok(
    file.create_directory_all(installation_dir),
    "Failed to create directory",
  )

  use _ <- assert_ok(
    file.write_bits(download_res.body, to: download_path),
    "Failed to write download to disk",
  )

  utils.set_progress(p, "Extracting download...")

  use _ <- assert_ok(
    unzip(download_path, installation_dir),
    "Failed to extract downloaded .zip archive",
  )

  use _ <- assert_ok(
    file.delete(download_path),
    "Failed to remove downloaded .zip archive! The installation should otherwise have succeeded.",
  )

  //  TODO! Set the executable bit on the chrome binary
  //        Because unzip does not preserve file permissions

  Ok(Nil)
}

type VersionItem {
  VersionItem(version: String, revision: String, downloads: List(DownloadItem))
}

type DownloadItem {
  DownloadItem(platform: String, url: String)
}

fn select_version(
  target: String,
  version_list: List(VersionItem),
) -> Result(VersionItem, Nil) {
  case target {
    "latest" -> {
      list.last(version_list)
    }
    _ -> {
      case string.contains(target, ".") {
        // Try for exact match
        True -> {
          list.find(version_list, fn(item) { item.version == target })
        }
        False -> {
          // Try to find first major version matching the target
          list.reverse(version_list)
          |> list.find(fn(item) {
            case string.split(item.version, ".") {
              [major, ..] if major == target -> True
              _ -> False
            }
          })
        }
      }
    }
  }
}

fn select_download(version: VersionItem, platform: String) {
  list.find(version.downloads, fn(item) { item.platform == platform })
}

fn parse_version_list(input: dynamic.Dynamic) {
  let download_item_decoder =
    dynamic.decode2(
      DownloadItem,
      dynamic.field("platform", dynamic.string),
      dynamic.field("url", dynamic.string),
    )
  let download_list_item_decoder = fn(list_item: dynamic.Dynamic) {
    dynamic.field("chrome", dynamic.list(download_item_decoder))(list_item)
  }
  let version_item_decoder =
    dynamic.decode3(
      VersionItem,
      dynamic.field("version", dynamic.string),
      dynamic.field("revision", dynamic.string),
      dynamic.field("downloads", download_list_item_decoder),
    )

  dynamic.field("versions", dynamic.list(version_item_decoder))(input)
}

fn resolve_platform() -> Result(String, String) {
  case os.family(), get_arch() {
    os.Darwin, "aarch64" <> _ -> {
      Ok("mac-arm64")
    }
    os.Darwin, _ -> {
      Ok("mac-x64")
    }
    os.Linux, "x86_64" <> _ -> {
      utils.warn(
        "You appear to be on linux, just to let you know, dependencies are not installed automatically by this script,
you must install them yourself! You may check `ldd chrome | grep not` to see what dependencies are missing.
See also: https://github.com/puppeteer/puppeteer/blob/main/docs/troubleshooting.md#chrome-doesnt-launch-on-linux",
      )
      Ok("linux64")
    }
    os.WindowsNt, "x86_64" <> _ -> {
      Ok("win64")
    }
    os.WindowsNt, _ -> {
      utils.warn(
        "The installer thinks you are on a 32-bit Windows system and is installing 32-bit Chrome, 
this is unusual, please verify this is correct",
      )
      Ok("win32")
    }
    _, architecture -> {
      utils.err("Could not resolve an appropriate platform for your system. 
Please note that the available platforms are limited by what Google Chrome for Testing supports,
notably, ARM64 on Linux is unfortunately not supported at the moment.
Your architecture is: " <> architecture <> ".")
      Error("Unsupported system: " <> architecture)
    }
  }
}

fn assert_is_json(
  res,
  human_error: String,
  apply fun: fn() -> Result(b, InstallationError),
) {
  case response.get_header(res, "content-type") {
    Ok("application/json") -> fun()
    Ok("application/json" <> _) -> fun()
    _ -> {
      io.println("")
      utils.err(human_error)
      Error(InstallationError)
    }
  }
}

fn assert_ok(
  result: Result(a, e),
  human_error: String,
  apply fun: fn(a) -> Result(b, InstallationError),
) -> Result(b, InstallationError) {
  case result {
    Ok(x) -> fun(x)
    Error(err) -> {
      io.println("")
      utils.err(human_error)
      io.debug(err)
      Error(InstallationError)
    }
  }
}

fn assert_true(
  condition: Bool,
  human_error: String,
  apply fun: fn() -> Result(a, InstallationError),
) -> Result(a, InstallationError) {
  case condition {
    True -> fun()
    False -> {
      io.println("")
      utils.err(human_error)
      Error(InstallationError)
    }
  }
}

fn new_download_request(url: String) {
  use base_req <- result.try(request.to(url))
  Ok(request.set_body(base_req, <<>>))
}

@external(erlang, "chrobot_ffi", "get_arch")
fn get_arch() -> String

@external(erlang, "chrobot_ffi", "unzip")
fn unzip(from: String, to: String) -> Result(Nil, dynamic.Dynamic)
