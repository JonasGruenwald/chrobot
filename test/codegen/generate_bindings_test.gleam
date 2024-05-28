import birdie
import codegen/generate_bindings.{
  apply_protocol_patches, gen_domain_module, gen_root_module,
  get_stable_protocol, merge_protocols, parse_protocol,
}
import gleam/list
import gleam/option
import gleeunit/should

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
  let inner_type_is_int = case node_id_type.inner {
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

pub fn gen_enum_encoder_decoder_test() {
  let enum_type_name = "CertificateTransparencyCompliance"
  let enum_values = ["unknown", "not-compliant", "compliant"]
  generate_bindings.gen_enum_encoder(enum_type_name, enum_values)
  |> birdie.snap(title: "Enum encoder function")
  generate_bindings.gen_enum_decoder(enum_type_name, enum_values)
  |> birdie.snap(title: "Enum decoder function")
}

/// Just run all the functions, see if anything panics.
/// We could snapshot the output here, but then again the output is just the codegen
/// that's written to `protocol/*` and committed to vcs so we already have snapshots of 
/// it and would just duplicate those.
pub fn general_bindings_gen_test() {
  let assert Ok(browser_protocol) =
    parse_protocol("./assets/browser_protocol.json")
  let assert Ok(js_protocol) = parse_protocol("./assets/js_protocol.json")
  let protocol =
    merge_protocols(browser_protocol, js_protocol)
    |> apply_protocol_patches()
  let stable_protocol = get_stable_protocol(protocol, False, False)
  gen_root_module(stable_protocol)
  list.each(stable_protocol.domains, fn(domain) {
    gen_domain_module(stable_protocol, domain)
  })
}
