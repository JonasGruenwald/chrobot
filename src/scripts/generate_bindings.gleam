//// This script generates gleam bindings to the Chrome DevTools Protocol
//// based on the protocol spec which is loaded from a local json file
//// 
//// 
//// TODO 
//// current note:
//// The types / parameters are implemented wrong, here is how it actually is:
//// * Object properties are parameters not types
//// * Types and parameters are almost identical, except for two things:
////    ->  Types have an 'id' and parameters have a 'name' instead
////    ->  Parameters have a "ref" type
//// 
//// 
//// New idea:
//// - Base type without name or id
//// - TypeDefinition wraps the BaseType with 'id'
//// - ParamDefinition wraps the BaseType with 'optional' and 'name'

import gleam/dynamic.{type Dynamic, bool, field, list, optional_field, string}
import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import simplifile as file

pub opaque type Protocol {
  Protocol(version: Version, domains: List(Domain))
}

pub opaque type Version {
  Version(major: String, minor: String)
}

pub opaque type Domain {
  Domain(
    domain: String,
    experimental: Option(Bool),
    dependencies: Option(List(String)),
    types: Option(List(TypeDefinition)),
    commands: List(Command),
    events: Option(List(Event)),
    description: Option(String),
  )
}

pub opaque type Type {
  // represents 'number', 'integer', 'string', 'boolean'
  // and for object properties: 'any'
  PrimitiveType(
    // this field just 'type' in the JSON
    // but that's a reserved keyword
    type_name: String,
  )
  // these are of type 'string' in the schema, but they have an enum array
  EnumType(enum: List(String))
  ObjectType(properties: Option(List(PropertyDefinition)))
  ArrayType(items: ArrayTypeItem)
  // This is a reference to another type
  // it may only appear in parameters and returns
  RefType(
    // this field is '$ref' in the JSON
    // it contains the domain name and the type name separated by '.'
    ref_target: String,
  )
}

pub opaque type ArrayTypeItem {
  ReferenceItem(ref_target: String)
  PrimitiveItem(type_name: String)
}

pub opaque type TypeDefinition {
  TypeDefinition(
    id: String,
    description: Option(String),
    experimental: Option(Bool),
    deprecated: Option(Bool),
    inner: Type,
  )
}

/// Property defintions are a type or a reference with some additional info
/// We use them to represent:
/// - Object Properties (for nesting)
/// - Command Parameters
/// - Command Returns
pub opaque type PropertyDefinition {
  PropertyDefinition(
    name: String,
    description: Option(String),
    experimental: Option(Bool),
    deprecated: Option(Bool),
    optional: Option(Bool),
    inner: Type,
  )
}

pub opaque type Command {
  // There is a 'redirect' field here which I'm ignoring
  // It's for hinting at the command being implemented in another domain
  Command(
    name: String,
    description: Option(String),
    experimental: Option(Bool),
    deprecated: Option(Bool),
    parameters: Option(List(PropertyDefinition)),
    returns: Option(List(Type)),
  )
}

pub opaque type Event {
  Event(
    name: String,
    description: Option(String),
    experimental: Option(Bool),
    deprecated: Option(Bool),
    parameters: List(Type),
  )
}

pub fn main() {
  let assert Ok(protocol) = parse_protocol("./assets/browser_protocol.json")
  io.println(
    "Browser protocol version: "
    <> protocol.version.major
    <> "."
    <> protocol.version.minor,
  )
}

fn parse_type_def(
  input: Dynamic,
) -> Result(TypeDefinition, List(dynamic.DecodeError)) {
  dynamic.decode5(
    TypeDefinition,
    field("id", string),
    optional_field("description", string),
    optional_field("experimental", bool),
    optional_field("deprecated", bool),
    // actual type is on the 'inner' attribute
    parse_type,
  )(input)
}

fn parse_property_def(
  input: Dynamic,
) -> Result(PropertyDefinition, List(dynamic.DecodeError)) {
  dynamic.decode6(
    PropertyDefinition,
    field("name", string),
    optional_field("description", string),
    optional_field("experimental", bool),
    optional_field("deprecated", bool),
    optional_field("optional", bool),
    // property always wraps a type (or reference to a type)
    parse_type,
  )(input)
}

/// For arrays we handle only primitive types or refs
fn parse_array_type_item(
  input: Dynamic,
) -> Result(ArrayTypeItem, List(dynamic.DecodeError)) {
  let ref = field("$ref", string)(input)
  let type_name = field("type", string)(input)
  case ref, type_name {
    Ok(ref_target), _ -> Ok(ReferenceItem(ref_target))
    _, Ok(type_name_val) -> Ok(PrimitiveItem(type_name_val))
    Error(any), _ -> Error(any)
  }
}

/// Parse a 'type' object from the protocol spec
/// This is also used to parse parameters and returns
/// Therefore it also parses and returns '$ref' types
/// which are not present in the top-level 'types' field
fn parse_type(input: Dynamic) -> Result(Type, List(dynamic.DecodeError)) {
  let primitive_type_decoder =
    dynamic.decode1(PrimitiveType, field("type", string))
  let enum_type_decoder = dynamic.decode1(EnumType, field("enum", list(string)))
  let object_type_decoder =
    dynamic.decode1(ObjectType, optional_field("properties", list(parse_property_def)))
  let array_type_decoder =
    dynamic.decode1(
      ArrayType,
      // you may think 'items' is an array, but nah, it's an object!
      field("items", parse_array_type_item),
    )
  let ref_type_decoder = dynamic.decode1(RefType, field("$ref", string))
  let type_name = field("type", string)(input)
  use enum <- result.try(optional_field("enum", list(string))(input))
  use ref <- result.try(optional_field("$ref", string)(input))
  case type_name, enum, ref {
    Ok("string"), Some(_enum), _ -> enum_type_decoder(input)
    Ok("string"), None, _
    | Ok("boolean"), _, _
    | Ok("number"), _, _
    | Ok("any"), _, _
    | Ok("integer"), _, _ -> primitive_type_decoder(input)
    Ok("object"), _, _ -> object_type_decoder(input)
    Ok("array"), _, _ -> array_type_decoder(input)
    _, _, Some(_ref) -> ref_type_decoder(input)
    Ok(unknown), _, _ ->
      Error([
        dynamic.DecodeError(
          expected: "A type with a valid 'type' field",
          found: unknown,
          path: ["parse_type"],
        ),
      ])
    Error(any), _, _ -> Error(any)
  }
}

// cheecky placeholder
fn todo_list_parser(_input: Dynamic) {
  Ok([])
}

fn parse_protocol(path from: String) -> Result(Protocol, json.DecodeError) {
  let assert Ok(json_string) = file.read(from: from)

  let domain_decoder =
    dynamic.decode7(
      Domain,
      field("domain", string),
      optional_field("experimental", bool),
      optional_field("dependencies", list(string)),
      optional_field("types", list(parse_type_def)),
      field("commands", todo_list_parser),
      optional_field("events", todo_list_parser),
      optional_field("description", string),
    )

  let version_decoder =
    dynamic.decode2(Version, field("major", string), field("minor", string))

  let protocol_decoder =
    dynamic.decode2(
      Protocol,
      field("version", version_decoder),
      field("domains", list(domain_decoder)),
    )

  json.decode(from: json_string, using: protocol_decoder)
}
