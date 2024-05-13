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

Chrobot provides a set of strongly typed bindings to the stable version of the [Chrome Devtools Protocol](https://chromedevtools.github.io/devtools-protocol/), based on its published JSON specification.

It also exposes some handy high level abstractions for browser automation, and handles starting a browser instance and communicating with it for you.

You could use it for 

* Generating PDFs from HTML
* Web scraping
* Web archiving
* Browser integration tests

> 🦝 The generated protocol bindings are largely untested and experimental, use at your own peril

## Setup

### Browser

Chrobot can use an existing system installation of Google Chrome or Chromium, if you already have one.

If you would like a hermetic installation of a specific version of a chrome build optimized for automation, I recommend using the [installation script from puppeteer](https://pptr.dev/browsers-api) to achieve this

```sh
# (you will need node.js to run this of course)
npx @puppeteer/browsers install chrome
```

The `chrobot.launch` / `chrome.launch` commands will attempt to find a local chrome installation like this, and prioritize it over your system installation.

Of course the most consistent way to launch a specific browser would be to pass a config with a browser path.

### Package

Install as a Gleam package

```sh
gleam add chrobot
```

## Examples

TODO

## Guide

TODO

## Documentation

The full documentation can be found at <https://hexdocs.pm/chrobot>.