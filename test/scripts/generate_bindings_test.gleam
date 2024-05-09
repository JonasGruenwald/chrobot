import gleam/list
import gleam/option
import gleeunit/should
import scripts/generate_bindings.{parse_protocol}

pub fn parse_browser_protocol_test() {
  let assert Ok(protocol) = parse_protocol("./assets/browser_protocol.json")
  protocol.version.major
  |> should.equal("1")

  // Let's find the DOM domain
  let assert Ok(dom_domain) =
    list.find(protocol.domains, fn(d) { d.domain == "DOM" })

  // It should have a types list
  option.is_some(dom_domain.types)
  |> should.be_true

  // The NodeId type should be on the DOM domain types
  let dom_types = option.unwrap(dom_domain.types, [])
  let assert Ok(node_id_type) = list.find(dom_types, fn(t) { t.id == "NodeId" })

  // NodeId should have an inner type of "integer"
  let assert inner_type_is_int = case node_id_type.inner {
    generate_bindings.PrimitiveType("integer") -> True
    _ -> False
  }
  inner_type_is_int
  |> should.equal(True)
}

pub fn parse_js_protocol_test() {
  let assert Ok(protocol) = parse_protocol("./assets/js_protocol.json")
  protocol.version.major
  |> should.equal("1")

  // Let's find the Runtime domain
  let assert Ok(runtime_domain) =
    list.find(protocol.domains, fn(d) { d.domain == "Runtime" })

  // It should have a types list
  option.is_some(runtime_domain.types)
  |> should.be_true

  // The DeepSerializedValue type should be on the Runtime domain types
  let runtime_types = option.unwrap(runtime_domain.types, [])
  let assert Ok(deep_serialized_value_type) =
    list.find(runtime_types, fn(t) { t.id == "DeepSerializedValue" })

  // DeepSerializedValue should have an inner type of "object" with properties
  let assert Ok(target_properties) = case deep_serialized_value_type.inner {
    generate_bindings.ObjectType(option.Some(properties)) -> Ok(properties)
    _ -> Error("Did not find ObjectType with some properties")
  }

  // There should be a property named "type" in there
  let assert Ok(type_property) =
    list.find(target_properties, fn(p) { p.name == "type" })

  // This "type" property should be of type string with enum values
  let assert Ok(enum_values) = case type_property.inner {
    generate_bindings.EnumType(values) -> Ok(values)
    _ -> Error("Property should was not an EnumType")
  }

  // One of the enum values should be "window"
  list.any(enum_values, fn(v) { v == "window" })
  |> should.be_true
}
