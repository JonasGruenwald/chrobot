import chrobot
import gleam/io

pub fn main() {
  // Open the browser and navigate to the gleam homepage
  let assert Ok(browser) = chrobot.launch()
  let assert Ok(page) =
    browser
    |> chrobot.open("file:///Users/jonas/Projects/chrobot/test_assets/reference_website.html", 30_000)

  let assert Ok(_) = chrobot.await_selector(page, "body")
  // Take a screeshot and save it as 'hi_lucy.png'
  let assert Ok(res) = chrobot.select_all(page, "a")
}
