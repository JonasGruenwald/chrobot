//// > ⚙️  This module was generated from the Chrome DevTools Protocol version **1.3**
//// ## Tracing Domain  
////
//// This protocol domain has no description.  
////
//// [📖   View this domain on the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/1-3/Tracing/)

// ---------------------------------------------------------------------------
// |  !!!!!!   This is an autogenerated file - Do not edit manually  !!!!!!  |
// | Run ` gleam run -m scripts/generate_protocol_bindings.sh` to regenerate.|  
// ---------------------------------------------------------------------------

import gleam/json
import gleam/option
import protocol/io

pub type TraceConfig {
  TraceConfig(
    included_categories: option.Option(List(String)),
    excluded_categories: option.Option(List(String)),
  )
}

@internal
pub fn encode__trace_config(value__: TraceConfig) {
  json.object([
    #("includedCategories", {
      case value__.included_categories {
        option.Some(value__) -> json.array(value__, of: json.string)
        option.None -> json.null()
      }
    }),
    #("excludedCategories", {
      case value__.excluded_categories {
        option.Some(value__) -> json.array(value__, of: json.string)
        option.None -> json.null()
      }
    }),
  ])
}
