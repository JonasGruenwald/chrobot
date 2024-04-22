import gleam/http.{Get}
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/io
import gleam/result
import gleeunit/should
import simplifile as file

const browser_protocol_url = "https://raw.githubusercontent.com/ChromeDevTools/devtools-protocol/master/json/browser_protocol.json"

const js_protocol_url = "https://raw.githubusercontent.com/ChromeDevTools/devtools-protocol/master/json/js_protocol.json"

const destination_dir = "./assets/"

/// Download the latest protocol JSON files from the official repository
/// And place them in the local assets folder
/// -- panic when anything goes wrong
pub fn main() {
  download(
    from: browser_protocol_url,
    to: destination_dir <> "browser_protocol.json",
  )
  download(from: js_protocol_url, to: destination_dir <> "js_protocol.json")
}

fn download(from origin_url: String, to destination_path: String) -> Nil {
  io.println("Making request to " <> origin_url)
  // Prepare a HTTP request record
  let assert Ok(request) = request.to(origin_url)

  // Send the HTTP request to the server
  let assert Ok(res) = httpc.send(request)

  // We get a response record back
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
