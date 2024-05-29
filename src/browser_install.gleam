//// This module provides basic browser installation functionality, allowing you
//// to install a local version of [Google Chrome for Testing](https://github.com/GoogleChromeLabs/chrome-for-testing) in the current directory on macOS and Linux.
//// 
//// ## Usage
////  
//// You may run browser installation directly with 
//// 
//// ```sh
//// gleam run -m browser_install
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
//// ## Caveats
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
//// ### Linux Dependencies
//// 
//// The tool does **not** install dependencies on Linux, you must install them yourself.
//// 
//// On debian / ubuntu based systems you may install dependencies with the following command:
//// 
//// ```sh
//// sudo apt-get update && sudo apt-get install -y \
//// ca-certificates \
//// fonts-liberation \
//// libasound2 \
//// libatk-bridge2.0-0 \
//// libatk1.0-0 \
//// libc6 \
//// libcairo2 \
//// libcups2 \
//// libdbus-1-3 \
//// libexpat1 \
//// libfontconfig1 \
//// libgbm1 \
//// libgcc1 \
//// libglib2.0-0 \
//// libgtk-3-0 \
//// libnspr4 \
//// libnss3 \
//// libpango-1.0-0 \
//// libpangocairo-1.0-0 \
//// libstdc++6 \
//// libx11-6 \
//// libx11-xcb1 \
//// libxcb1 \
//// libxcomposite1 \
//// libxcursor1 \
//// libxdamage1 \
//// libxext6 \
//// libxfixes3 \
//// libxi6 \
//// libxrandr2 \
//// libxrender1 \
//// libxss1 \
//// libxtst6 \
//// lsb-release \
//// wget \
//// xdg-utils
//// ```

import chrobot/internal/utils
import chrome
import filepath as path
import gleam/dynamic
import gleam/erlang/os
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/io
import gleam/json
import gleam/list
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

  // Find the executable binary 
  use haystack <- assert_ok(
    file.get_files(installation_dir),
    "Failed to scan installation directory for executable",
  )

  use executable <- assert_ok(
    list.find(haystack, fn(file) {
      chrome.is_local_chrome_path(file, os.family())
    }),
    "Failed to find executable in installation directory",
  )

  utils.stop_progress(p)

  case os.family() {
    os.Linux -> {
      utils.hint(
        "You can run the following command to check wich depencies are missing on your system:",
      )
      utils.show_cmd("ldd \"" <> executable <> "\" | grep not")
    }
    _ -> Nil
  }

  utils.info(
    "Chrome for Testing ("
    <> version.version
    <> ") installed successfully! The executable is located at:\n"
    <> executable
    <> "\n"
    <> "When using the `launch` command, chrobot should automatically use this local installation.",
  )

  Ok(executable)
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
      io.println("")
      utils.warn(
        "You appear to be on linux, just to let you know, dependencies are not installed automatically by this script,
you must install them yourself! Please check the docs of the install module for further information.",
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

/// Attempt unzip of the downloaded file  
/// Notes:
/// The erlang standard library unzip function, does not restore file permissions, and 
/// chrome consists of a bunch of executables, setting them all to executable
/// manually is a bit annoying.
/// Therefore, we try to use the system unzip command via a shell instead,
/// and only fall back to the erlang unzip if that fails.
fn unzip(from: String, to: String) {
  run_command("unzip -q " <> from <> " -d " <> to)
  use installation_dir_entries <- result.try(
    file.read_directory(to)
    |> result.replace_error(Nil),
  )

  let was_extracted =
    list.map(installation_dir_entries, fn(i) {
      file.verify_is_directory(path.join(to, i))
    })
    |> list.any(fn(check) {
      case check {
        Ok(True) -> True
        _ -> False
      }
    })

  case was_extracted {
    True -> Ok(Nil)
    False -> {
      // In this fallback method we extract the zip using erlang unzip, and then set the executable bit on all files
      // As you can imagine, this is not ideal, and may cause issues, therefore we warn the user.
      utils.warn(
        "Failed to extract downloaded .zip archive using system unzip command, falling back to erlang unzip.
You might run into permission issues when attempting to run the installed binary, this is not ideal!",
      )
      use _ <- result.try(erl_unzip(from, to))
      use installation_files <- result.try(
        file.get_files(to)
        |> result.replace_error(Nil),
      )
      list.each(installation_files, fn(i) {
        case file.verify_is_file(i) {
          Ok(True) -> {
            let _ = set_executable(i)
            Nil
          }
          _ -> {
            Nil
          }
        }
      })
      Ok(Nil)
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
fn erl_unzip(from: String, to: String) -> Result(Nil, Nil)

@external(erlang, "chrobot_ffi", "run_command")
fn run_command(command: String) -> String

@external(erlang, "chrobot_ffi", "set_executable")
fn set_executable(file: String) -> Result(Nil, Nil)
