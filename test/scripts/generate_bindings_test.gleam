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
