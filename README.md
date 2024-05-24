<p align="center"> 
<img src="https://raw.githubusercontent.com/JonasGruenwald/chrobot/main/doc_assets/header_1.png" alt="" style="max-width: 450px; width: 100%;">
</p>

<h1 align="center">Chrobot</h1>

<p align="center">
⛭ Typed browser automation for the BEAM ⛭
</p>
<p align="center">
<a href="https://hex.pm/packages/chrobot">
  <img src="https://img.shields.io/hexpm/v/chrobot" alt="Package Version">
</a>
<a href="https://hexdocs.pm/chrobot/">
  <img src="https://img.shields.io/badge/hex-docs-ffaff3" alt="Hex Docs">
</a>
<img alt="Target: Erlang" src="https://img.shields.io/badge/target-erlang-red?logo=erlang">
</p>

## About

Chrobot provides a set of typed bindings to the stable version of the [Chrome Devtools Protocol](https://chromedevtools.github.io/devtools-protocol/), based on its published JSON specification.

The typed interface is achieved by generating Gleam code for type definitions as well as encoder / decoder functions from the parsed JSON specification file.

Chrobot also exposes some handy high level abstractions for browser automation, and handles managing a browser instance via an Erlang Port and communicating with it for you.

You could use it for 

* Generating PDFs from HTML
* Web scraping
* Web archiving
* Browser integration tests

> 🦝 The generated protocol bindings are largely untested and I would consider this package experimental, use at your own peril!

## Setup

### Browser

Chrobot can use an existing system installation of Google Chrome or Chromium, if you already have one.

Chrobot also comes with a simple utility to install a version of [Google Chrome for Testing](https://github.com/GoogleChromeLabs/chrome-for-testing) directly inside your project.
Chrobot will automatically pick up this local installation when started via the `launch` command, and will prioritise it over a system installation of Google Chrome.

You can run the browser installer utility like so:
```sh
gleam run -m chrobot/install
```

Please [check the `install` docs for more information](https://hexdocs.pm/chrobot/install.html) – this installation method will not work everywhere and comes with some caveats!


### Package

Install as a Gleam package

```sh
gleam add chrobot
```

Install as an Elixir dependency with mix

```elixir
# in your mix.exs
defp deps do
  [
    {:chrobot, "~> 2.0.0", app: false, manager: :rebar3}
  ]
end
```

## Examples

### Take a screenshot of a website

```gleam
import chrobot

pub fn main() {
  // Open the browser and navigate to the gleam homepage
  let assert Ok(browser) = chrobot.launch()
  let assert Ok(page) =
    browser
    |> chrobot.open("https://gleam.run", 30_000)
  let assert Ok(_) = chrobot.await_selector(page, "body")
  
  // Take a screeshot and save it as 'hi_lucy.png'
  let assert Ok(screenshot) = chrobot.screenshot(page)
  let assert Ok(_) = chrobot.to_file(screenshot, "hi_lucy")
  let assert Ok(_) = chrobot.quit(browser)
}
```

### Generate a PDF document with [lustre](http://lustre.build/)

```gleam
import chrobot
import lustre/element.{text}
import lustre/element/html

fn build_page() {
  html.body([], [
    html.h1([], [text("Spanakorizo")]),
    html.h2([], [text("Ingredients")]),
    html.ul([], [
      html.li([], [text("1 onion")]),
      html.li([], [text("1 clove(s) of garlic")]),
      html.li([], [text("70 g olive oil")]),
      html.li([], [text("salt")]),
      html.li([], [text("pepper")]),
      html.li([], [text("2 spring onions")]),
      html.li([], [text("1/2 bunch dill")]),
      html.li([], [text("250 g round grain rice")]),
      html.li([], [text("150 g white wine")]),
      html.li([], [text("1 liter vegetable stock")]),
      html.li([], [text("1 kilo spinach")]),
      html.li([], [text("lemon zest, of 2 lemons")]),
      html.li([], [text("lemon juice, of 2 lemons")]),
    ]),
    html.h2([], [text("To serve")]),
    html.ul([], [
      html.li([], [text("1 lemon")]),
      html.li([], [text("feta cheese")]),
      html.li([], [text("olive oil")]),
      html.li([], [text("pepper")]),
      html.li([], [text("oregano")]),
    ]),
  ])
  |> element.to_document_string()
}

pub fn main() {
  let assert Ok(browser) = chrobot.launch()
  let assert Ok(page) =
    browser
    |> chrobot.create_page(build_page(), 10_000)

  // Store as 'recipe.png'
  let assert Ok(doc) = chrobot.pdf(page)
  let assert Ok(_) = chrobot.to_file(doc, "recipe")
  let assert Ok(_) = chrobot.quit(browser)
}
```

### Scrape a Website

> 🍄‍🟫 **Just a quick reminder:**  
> Please be mindful of the load you are putting on other people's web services when you are scraping them programmatically!  


```gleam
import chrobot
import gleam/io
import gleam/list
import gleam/result

pub fn main() {
  let assert Ok(browser) = chrobot.launch()
  let assert Ok(page) =
    browser
    |> chrobot.open("https://books.toscrape.com/", 30_000)

  let assert Ok(_) = chrobot.await_selector(page, "body")
  let assert Ok(page_items) = chrobot.select_all(page, ".product_pod h3 a")
  let assert Ok(title_results) =
    list.map(page_items, fn(i) { chrobot.get_attribute(page, i, "title") })
    |> result.all()
  io.debug(title_results)
  let assert Ok(_) = chrobot.quit(browser)
}

```

### Using from Elixir

```elixir
# ( output / logging removed for brevity )
iex(1)> {:ok, browser} = :chrobot.launch()
iex(2)> {:ok, page} = :chrobot.open(browser, "https://example.com", 10_000)
iex(3)> {:ok, object} = :chrobot.select(page, "h1")
iex(4)> {:ok,text} = :chrobot.get_text(page, object)
iex(5)> text
"Example Domain"
```


## Documentation & Guide

The full documentation can be found at <https://hexdocs.pm/chrobot>.

🗼 To learn about the high level abstractions, look at the [`chrobot` module documentation](https://hexdocs.pm/chrobot/chrobot.html).

📠 To learn how to use the protocol bindings directly, look at the [`protocol` module documentation](https://hexdocs.pm/chrobot/protocol.html).

