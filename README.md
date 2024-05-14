<p align="center"> 
<img src="https://raw.githubusercontent.com/JonasGruenwald/chrobot/main/docs/header_1.png" alt="" style="max-width: 450px">
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
</p>

## About

Chrobot provides a set of typed bindings to the stable version of the [Chrome Devtools Protocol](https://chromedevtools.github.io/devtools-protocol/), based on its published JSON specification.

It also exposes some handy high level abstractions for browser automation, and handles starting a browser instance and communicating with it for you.

You could use it for 

* Generating PDFs from HTML
* Web scraping
* Web archiving
* Browser integration tests

> 🦝 The generated protocol bindings are largely untested and I would consider this package experimental, use at your own peril

## Setup

### Browser

Chrobot can use an existing system installation of Google Chrome or Chromium, if you already have one.

If you would like a hermetic installation of a specific version of a chrome build optimized for automation, I recommend using the [installation script from puppeteer](https://pptr.dev/browsers-api) to achieve this

```sh
# (you will need node.js to run this of course)
npx @puppeteer/browsers install chrome
```

The `chrobot.launch` / `chrome.launch` commands will attempt to find a local chrome installation like this, and prioritize it over your system installation.

### Package

Install as a Gleam package

```sh
gleam add chrobot
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
    |> chrobot.open("https://gleam.run", 10_000)

  // Take a screeshot and save it as 'hi_lucy.png'
  let assert Ok(screenshot) = chrobot.screenshot(page)
  let assert Ok(_) = chrobot.to_file(screenshot, "hi_lucy")
  let assert Ok(_) = chrobot.quit(browser)
}

```

### Generate a PDF document with [lustre](http://lustre.build/)

```gleam
import chrobot
import gleam/io
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
  // Open the browser and navigate to the gleam homepage
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


## Documentation & Guide

The full documentation can be found at <https://hexdocs.pm/chrobot>.

🗼 To learn about the high level abstractions, look at the `chrobot` module documentation.

📠 To learn how to use the protocol bindings directly, look at the `protocol` module documentation.

