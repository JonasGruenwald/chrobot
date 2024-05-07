//// This script generates gleam bindings to the Chrome DevTools Protocol
//// based on the protocol spec which is loaded from a local json file
//// 
//// 1. The protocol JSON file is first parsed into an internal representation
//// 
//// Parsing Notes:  
//// We use the common 'Type' type to deal with the base concept of types in the
//// protocol, this includes top  level type definitions, object properties,
//// command parameters and command returns, which all wrap 'Type' with some 
//// additional attributes on top.
//// 
//// 2. Files are generated based on the parsed protocol
//// 
//// Codegen Notes:
//// - A root file `src/protocol.gleam` is generated with general information
//// - A module is generated for each domain in the protocol under `src/protocol/`
//// - Generated files should be put through `gleam format` before committing
//// 
//// This script will panic if anything goes wrong, do not import this module anywere

import gleam/dynamic.{field, optional_field} as d
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/string_builder as sb
import justin.{snake_case}
import simplifile as file

pub type Protocol {
  Protocol(version: Version, domains: List(Domain))
}

pub type Version {
  Version(major: String, minor: String)
}

pub type Domain {
  Domain(
    domain: String,
    experimental: Option(Bool),
    deprecated: Option(Bool),
    dependencies: Option(List(String)),
    types: Option(List(TypeDefinition)),
    commands: List(Command),
    events: Option(List(Event)),
    description: Option(String),
  )
}

pub type Type {
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

pub type ArrayTypeItem {
  ReferenceItem(ref_target: String)
  PrimitiveItem(type_name: String)
}

pub type TypeDefinition {
  TypeDefinition(
    id: String,
    description: Option(String),
    experimental: Option(Bool),
    deprecated: Option(Bool),
    inner: Type,
  )
}

/// Property defintions are a type or a reference with some additional info.
/// We use them to represent:
/// - Object Properties (for nesting)
/// - Command Parameters
/// - Command Returns
pub type PropertyDefinition {
  PropertyDefinition(
    name: String,
    description: Option(String),
    experimental: Option(Bool),
    deprecated: Option(Bool),
    optional: Option(Bool),
    inner: Type,
  )
}

pub type Command {
  // There is a 'redirect' field here which I'm ignoring
  // It's for hinting at the command being implemented in another domain
  Command(
    name: String,
    description: Option(String),
    experimental: Option(Bool),
    deprecated: Option(Bool),
    parameters: Option(List(PropertyDefinition)),
    returns: Option(List(PropertyDefinition)),
  )
}

pub type Event {
  Event(
    name: String,
    description: Option(String),
    experimental: Option(Bool),
    deprecated: Option(Bool),
    parameters: Option(List(PropertyDefinition)),
  )
}

pub fn main() {
  let assert Ok(browser_protocol) =
    parse_protocol("./assets/browser_protocol.json")
  let assert Ok(js_protocol) = parse_protocol("./assets/js_protocol.json")
  let protocol = merge_protocols(browser_protocol, js_protocol)
  io.println(
    "Browser protocol version: "
    <> protocol.version.major
    <> "."
    <> protocol.version.minor,
  )
  print_protocol_stats(protocol)
  let stable_protocol = get_stable_protocol(protocol)
  io.println("Stable protocol (experimental items removed):")
  print_protocol_stats(stable_protocol)
  let target = "src/protocol.gleam"
  io.println("Writing root protocol module to: " <> target)
  let assert Ok(_) = file.write(gen_root_module(stable_protocol), to: target)
  let assert Ok(_) = file.create_directory_all("src/protocol")
  list.each(stable_protocol.domains, fn(domain) {
    let target = "src/protocol/" <> snake_case(domain.domain) <> ".gleam"
    io.println("Writing domain module to: " <> target)
    let assert Ok(_) =
      file.write(gen_domain_module(stable_protocol, domain), to: target)
  })
}

// --- UTILS ---

fn get_protocol_stats(protocol: Protocol) {
  #(
    // Number of domains in protocol
    list.length(protocol.domains),
    // Total number of types in protocol
    list.flat_map(protocol.domains, fn(d) {
      case d.types {
        Some(types) -> types
        None -> []
      }
    })
      |> list.length(),
    // Total number of commands in protocol
    list.flat_map(protocol.domains, fn(d) { d.commands })
      |> list.length(),
    // Total number of events in protocol
    list.flat_map(protocol.domains, fn(d) {
      case d.events {
        Some(events) -> events
        None -> []
      }
    })
      |> list.length(),
  )
}

fn get_stable_propdef(
  propdef: PropertyDefinition,
) -> Result(PropertyDefinition, Nil) {
  case propdef.experimental, propdef.deprecated {
    Some(True), _ -> Error(Nil)
    _, Some(True) -> Error(Nil)
    _, _ -> Ok(propdef)
  }
}

fn get_stable_event(event: Event) -> Result(Event, Nil) {
  case event.experimental, event.deprecated {
    Some(True), _ -> Error(Nil)
    _, Some(True) -> Error(Nil)
    _, _ ->
      Ok(
        Event(
          name: event.name,
          description: event.description,
          experimental: event.experimental,
          deprecated: event.deprecated,
          parameters: {
            case event.parameters {
              Some(params) ->
                Some(list.filter_map(params, get_stable_propdef))
              None -> None
            }
          },
        ),
      )
  }
}

fn get_stable_command(command: Command) -> Result(Command, Nil) {
  case command.experimental, command.deprecated {
    Some(True), _ -> Error(Nil)
    _, Some(True) -> Error(Nil)
    _, _ ->
      Ok(
        Command(
          name: command.name,
          description: command.description,
          experimental: command.experimental,
          deprecated: command.deprecated,
          parameters: {
            case command.parameters {
              Some(params) ->
                Some(list.filter_map(params, get_stable_propdef))
              None -> None
            }
          },
          returns: {
            case command.returns {
              Some(returns) ->
                Some(list.filter_map(returns, get_stable_propdef))
              None -> None
            }
          },
        ),
      )
  }
}

fn get_stable_type(param_type: TypeDefinition) -> Result(TypeDefinition, Nil) {
  case param_type.experimental, param_type.deprecated {
    Some(True), _ -> Error(Nil)
    _, Some(True) -> Error(Nil)
    _, _ -> Ok(param_type)
  }
}

/// Return the protocol with experimental domains, types, commands, parameters and events removed.  
/// Note: The protocol still contains deprecated items, and the 'experimental' field is not removed.
/// The check is NOT performed recursively into nested types / property definitions, just at the top level.
/// Note that this might leave some optional lists as empty if all items are experimental.
pub fn get_stable_protocol(protocol: Protocol) -> Protocol {
  Protocol(
    version: protocol.version,
    domains: list.filter_map(protocol.domains, fn(domain) {
      case domain.experimental, domain.deprecated {
        Some(True), _ -> Error(Nil)
        _, Some(True) -> Error(Nil)
        _, _ -> {
          Ok(Domain(
            domain: domain.domain,
            experimental: domain.experimental,
            deprecated: domain.deprecated,
            dependencies: domain.dependencies,
            types: {
              case domain.types {
                Some(types) ->
                  Some(list.filter_map(types, get_stable_type))
                None -> None
              }
            },
            commands: list.filter_map(
              domain.commands,
              get_stable_command,
            ),
            events: {
              case domain.events {
                Some(events) ->
                  Some(list.filter_map(events, get_stable_event))
                None -> None
              }
            },
            description: domain.description,
          ))
        }
      }
    }),
  )
}

fn merge_protocols(left: Protocol, right: Protocol) -> Protocol {
  let assert True = left.version == right.version
  Protocol(
    version: left.version,
    domains: list.append(left.domains, right.domains),
  )
}

fn print_protocol_stats(protocol: Protocol) {
  let #(num_domains, num_types, num_commands, num_events) =
    get_protocol_stats(protocol)
  io.println(
    "Protocol Stats: "
    <> "Domains: "
    <> int.to_string(num_domains)
    <> ", Types: "
    <> int.to_string(num_types)
    <> ", Commands: "
    <> int.to_string(num_commands)
    <> ", Events: "
    <> int.to_string(num_events),
  )
  Nil
}

// --- PARSING ---

fn parse_type_def(
  input: d.Dynamic,
) -> Result(TypeDefinition, List(d.DecodeError)) {
  d.decode5(
    TypeDefinition,
    field("id", d.string),
    optional_field("description", d.string),
    optional_field("experimental", d.bool),
    optional_field("deprecated", d.bool),
    // actual type is on the 'inner' attribute
    parse_type,
  )(input)
}

fn parse_property_def(
  input: d.Dynamic,
) -> Result(PropertyDefinition, List(d.DecodeError)) {
  d.decode6(
    PropertyDefinition,
    field("name", d.string),
    optional_field("description", d.string),
    optional_field("experimental", d.bool),
    optional_field("deprecated", d.bool),
    optional_field("optional", d.bool),
    // property always wraps a type (or reference to a type)
    parse_type,
  )(input)
}

/// For arrays we handle only primitive types or refs
fn parse_array_type_item(
  input: d.Dynamic,
) -> Result(ArrayTypeItem, List(d.DecodeError)) {
  let ref = field("$ref", d.string)(input)
  let type_name = field("type", d.string)(input)
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
fn parse_type(input: d.Dynamic) -> Result(Type, List(d.DecodeError)) {
  let primitive_type_decoder = d.decode1(PrimitiveType, field("type", d.string))
  let enum_type_decoder = d.decode1(EnumType, field("enum", d.list(d.string)))
  let object_type_decoder =
    d.decode1(
      ObjectType,
      optional_field("properties", d.list(parse_property_def)),
    )
  let array_type_decoder =
    d.decode1(
      ArrayType,
      // you may think 'items' is an array, but nah, it's an object!
      field("items", parse_array_type_item),
    )
  let ref_type_decoder = d.decode1(RefType, field("$ref", d.string))
  let type_name = field("type", d.string)(input)
  use enum <- result.try(optional_field("enum", d.list(d.string))(input))
  use ref <- result.try(optional_field("$ref", d.string)(input))
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
        d.DecodeError(
          expected: "A type with a valid 'type' field",
          found: unknown,
          path: ["parse_type"],
        ),
      ])
    Error(any), _, _ -> Error(any)
  }
}

pub fn parse_protocol(path from: String) -> Result(Protocol, json.DecodeError) {
  let assert Ok(json_string) = file.read(from: from)

  let command_decoder =
    d.decode6(
      Command,
      field("name", d.string),
      optional_field("description", d.string),
      optional_field("experimental", d.bool),
      optional_field("deprecated", d.bool),
      optional_field("parameters", d.list(parse_property_def)),
      optional_field("returns", d.list(parse_property_def)),
    )

  let event_decoder =
    d.decode5(
      Event,
      field("name", d.string),
      optional_field("description", d.string),
      optional_field("experimental", d.bool),
      optional_field("deprecated", d.bool),
      optional_field("parameters", d.list(parse_property_def)),
    )

  let domain_decoder =
    d.decode8(
      Domain,
      field("domain", d.string),
      optional_field("experimental", d.bool),
      optional_field("deprecated", d.bool),
      optional_field("dependencies", d.list(d.string)),
      optional_field("types", d.list(parse_type_def)),
      field("commands", d.list(command_decoder)),
      optional_field("events", d.list(event_decoder)),
      optional_field("description", d.string),
    )

  let version_decoder =
    d.decode2(Version, field("major", d.string), field("minor", d.string))

  let protocol_decoder =
    d.decode2(
      Protocol,
      field("version", version_decoder),
      field("domains", d.list(domain_decoder)),
    )

  json.decode(from: json_string, using: protocol_decoder)
}

// --- CODEGEN ---

fn gen_preamble(protocol: Protocol) {
  "
// ---------------------------------------------------------------------------
// |  !!!!!!   This is an autogenerated file - Do not edit manually  !!!!!!  |
// | Run ` gleam run -m scripts/generate_protocol_bindings.sh` to regenerate.|  
// ---------------------------------------------------------------------------
//// > This module was generated from the Chrome DevTools Protocol version **" <> protocol.version.major <> "." <> protocol.version.minor <> "**\n"
}

fn gen_function_comment(content: String) {
  "/// " <> content <> "\n"
}

/// Generate the root module for the protocol bindings
/// This is just an entrypoint with some documentation, and the version number
pub fn gen_root_module(protocol: Protocol) {
  sb.new()
  |> sb.append(gen_preamble(protocol))
  |> sb.append(
    "////
//// This is the protocol definition entrypoint, which contains protocol version information.  
//// Each domain in the protocol is represented as a submodule under `/protocol`.  \n////\n",
  )
  |> sb.append(
    "//// For reference: [See the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/",
  )
  |> sb.append(protocol.version.major)
  |> sb.append("-")
  |> sb.append(protocol.version.minor)
  |> sb.append("/")
  |> sb.append(")\n\n")
  |> sb.append("const version_major = \"" <> protocol.version.major <> "\"\n")
  |> sb.append("const version_minor = \"" <> protocol.version.minor <> "\"\n\n")
  |> sb.append(gen_function_comment(
    "Get the protocol version as a tuple of major and minor version",
  ))
  |> sb.append("pub fn version() { #(version_major, version_minor)}\n")
  |> sb.to_string()
}

fn multiline_module_comment(content: String) {
  string.replace(content, "\n", "\n//// ")
}

fn gen_domain_module_header(protocol: Protocol, domain: Domain) {
  sb.new()
  |> sb.append("//// ## " <> domain.domain <> " Domain")
  |> sb.append("  \n////\n")
  |> sb.append("//// ")
  |> sb.append(
    option.unwrap(
      domain.description,
      "This protocol domain has no description.",
    )
    |> multiline_module_comment(),
  )
  |> sb.append("  \n////\n")
  |> sb.append(
    "//// [View this domain on the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/",
  )
  |> sb.append(protocol.version.major)
  |> sb.append("-")
  |> sb.append(protocol.version.minor)
  |> sb.append("/")
  |> sb.append(domain.domain)
  |> sb.append("/)\n\n")
}

pub fn gen_domain_module(protocol: Protocol, domain: Domain) {
  sb.new()
  |> sb.append(gen_preamble(protocol))
  |> sb.append_builder(gen_domain_module_header(protocol, domain))
  |> sb.to_string()
}
