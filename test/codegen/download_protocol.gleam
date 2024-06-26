//// Download the latest protocol JSON files from the official repository
//// and place them in the local assets folder.
//// 
//// Protocol Repo is here:
//// https://github.com/ChromeDevTools/devtools-protocol
//// 
//// This script will panic if anything goes wrong, do not import this module anywere

import gleam/http/request
import gleam/httpc
import gleam/io
import simplifile as file

const browser_protocol_url = "https://raw.githubusercontent.com/ChromeDevTools/devtools-protocol/master/json/browser_protocol.json"

const js_protocol_url = "https://raw.githubusercontent.com/ChromeDevTools/devtools-protocol/master/json/js_protocol.json"

const destination_dir = "./assets/"

pub fn main() {
  download(
    from: browser_protocol_url,
    to: destination_dir <> "browser_protocol.json",
  )
  download(from: js_protocol_url, to: destination_dir <> "js_protocol.json")
}

fn download(from origin_url: String, to destination_path: String) -> Nil {
  io.println("Making request to " <> origin_url)
  let assert Ok(request) = request.to(origin_url)
  let assert Ok(res) = httpc.send(request)
  case res.status {
    200 -> {
      io.println("Writing response to " <> destination_path)
      let assert Ok(_) = file.write(res.body, to: destination_path)
      Nil
    }
    _ -> {
      io.println("Non-200 response from server!")
      panic
    }
  }
}
