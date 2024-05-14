import chrobot
import gleam/io
import protocol/runtime

pub fn main() {
  // Open the browser and navigate to the gleam homepage
  let assert Ok(browser) = chrobot.launch()
  let assert Ok(page) =
    browser
    |> chrobot.open("https://books.toscrape.com/", 10_000)

  let caller = chrobot.page_caller(page)
}
