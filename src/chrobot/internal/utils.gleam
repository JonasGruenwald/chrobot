import gleam/json
import gleam/option

pub fn add_optional(
  prop_encoders: List(#(String, json.Json)),
  value: option.Option(a),
  callback: fn(a) -> #(String, json.Json),
) {
  case value {
    option.Some(a) -> [callback(a), ..prop_encoders]
    option.None -> prop_encoders
  }
}
