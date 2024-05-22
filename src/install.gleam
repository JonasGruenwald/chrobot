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
/// 
/// [>‿0]
import chrobot/internal/utils
import filepath as path
import gleam/erlang/os
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
  utils.info(
    "Preparing to install chrome for testing ("
    <> target_version
    <> ") to "
    <> {
      case target_path {
        "." -> "current directory"
        _ -> target_path
      }
    },
  )
  todo
}
