//// The test server listens on localhost and returns some fixed data,
//// it can be used in tests, to avoid the need to request an external website

import chrobot/internal/utils
import gleam/bytes_builder
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/string
import mist.{type Connection, type ResponseData}

pub fn get_port() -> Int {
  8182
}

pub fn get_url() -> String {
  "http://localhost:" <> int.to_string(get_port()) <> "/"
}

pub fn start() {
  let not_found =
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_builder.from_string("Not found!")))

  let result =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        [] -> return_test_page(req)
        _ -> not_found
      }
    }
    |> mist.new
    |> mist.port(get_port())
    |> mist.start_http

  case result {
    Ok(_) -> Nil
    Error(err) -> {
      utils.err("The chrobot test server failed to start!
The server tries to list on on port " <> int.to_string(get_port()) <> ", perhaps it's in use?")
      panic as string.inspect(err)
    }
  }
}

pub type MyMessage {
  Broadcast(String)
}

fn return_test_page(_request: Request(Connection)) -> Response(ResponseData) {
  let body =
    "
  <html>
    <head>
      <title>Chrobot Test Page</title>
    </head>
    <body>
      <h1>Chrobot Test Page</h1>
      <div id=\"wibble\">wobble</div>
    </body>
  </html>
  "

  response.new(200)
  |> response.set_body(mist.Bytes(bytes_builder.from_string(body)))
  |> response.set_header("content-type", "text/html")
}
