# justin (Fork)

Forked from: https://github.com/lpil/justin

Convert between snake_case, camelCase, and other cases in Gleam.

[![Package Version](https://img.shields.io/hexpm/v/justin)](https://hex.pm/packages/justin)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/justin/)

```sh
gleam add justin
```
```gleam
import justin

pub fn main() {
  justin.snake_case("Hello World")
  // -> "hello_world"

  justin.camel_case("Hello World")
  // -> "helloWorld"

  justin.pascal_case("Hello World")
  // -> "HelloWorld"

  justin.kebab_case("Hello World")
  // -> "hello-world

  justin.sentence_case("hello-world")
  // -> "Hello world"
}
```

Further documentation can be found at <https://hexdocs.pm/justin>.

## Fork Notes

This fork of lpil/justin adds support for the following use case:

```gleam
  justin.snake_case("DOMDebugger")
  |> should.equal("dom_debugger")
  justin.snake_case("CSSLayerData")
  |> should.equal("css_layer_data")
```

Which is deliberately not supported upstream, see:
https://github.com/lpil/justin/pull/2