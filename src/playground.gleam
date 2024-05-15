import chrobot.{as_value, eval}
import gleam/dynamic
import gleam/io
import gleam/option.{type Option, None, Some}
import protocol/runtime

pub fn main() {
  // Open the browser and navigate to the gleam homepage
  let assert Ok(browser) = chrobot.launch()
  let assert Ok(page) =
    browser
    |> chrobot.open("https://books.toscrape.com/", 10_000)

  let assert Ok(remote_object_id) =
    chrobot.await_selector(page, ".product_pod > h3 > a")
  let assert Ok(data) =
    chrobot.get_attribute(on: page, from: remote_object_id, name: "title")
  let assert Ok(textprop) = chrobot.get_text(page, remote_object_id)

  let assert Ok(url) =
    eval(page, "window.location.href")
    |> as_value(dynamic.string)

  let assert Ok(outer_html) = chrobot.get_outer_html(page)

  io.debug(outer_html)
}
