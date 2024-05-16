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
//// 2. The parsed protocol is processed
////  - A stable version of the protocol is generated with experimental and deprecated items removed (can be toggled)
////  - Hardcoded patches are applied to the protocol to make it possible to generate bindings (e.g. replacing references with actual types to avoid circular dependencies)
//// 
//// 3. Files are generated based on the parsed protocol
//// 
//// Codegen Notes:
//// - A root file `src/protocol.gleam` is generated with general information
//// - A module is generated for each domain in the protocol under `src/protocol/`
//// - Generated files should be put through `gleam format` before committing
//// 
//// This script will panic if anything goes wrong, do not import this module anywere except for tests
//// 

// TODO: Attach comments to variants generated in type definitions

import gleam/dynamic.{field, optional_field} as d
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regex
import gleam/result
import gleam/string
import gleam/string_builder as sb
import justin.{pascal_case, snake_case}
import simplifile as file

const root_module_comment = "
This is the protocol definition entrypoint, it contains an overview of the protocol structure,
and a function to retrieve the version of the protocol used to generate the current bindings.  
The protocol version is also displayed in the box above, which appears on every generated module.  

## ⚠️ Really Important Notes
   
1) It's best never to work with the DOM domain for automation, 
[an explanation of why can be found here](https://github.com/puppeteer/puppeteer/pull/71#issuecomment-314599749).  
Instead, to automate DOM interaction, JavaScript can be injected using the Runtime domain.
  
2) Unfortunately, I haven't found a good way to map dynamic properties to gleam attributes bidirectionally.  
**This means all dynamic values you supply to commands will be silently dropped**!  
It's important to realize this to avoid confusion, for example in `runtime.call_function_on` 
you may want to supply arguments which can be any value, but it won't work.  
The only path to do that as far as I can tell, is write the protocol call logic yourself,
perhaps taking the codegen code as a basis.  
Check the `call_custom_function_on` function from `chrobot` which does this for the mentioned function

## Structure

Each domain in the protocol is represented as a module under `protocol/`. 

In general, the bindings are generated through codegen, directly from the JSON protocol schema [published here](https://github.com/ChromeDevTools/devtools-protocol), 
however there are some little adjustments that needed to be made, to make the protocol schema usable, mainly due to
what I believe are minor bugs in the protocol.  
To see these changes, check the `apply_protocol_patches` function in `chrobot/internal/generate_bindings`.

Domains may depend on the types of other domains, these dependencies are mirrored in the generated bindings where possible.
In some case, type references to other modules have been replaced by the respective inner type, because the references would
create a circular dependency.

## Types 

The generated bindings include a mirror of the type defitions of each type in the protocol spec,
alongside with an `encode__` function to encode the type into JSON in order to send it to the browser
and a `decode__` function in order to decode the type out of a payload sent from the browser. Encoders and
decoders are marked internal and should be used through command functions which are described below.

Notes:  
- Some object properties in the protocol have the type `any`, in this case the value is considered as dynamic
by decoders, and encoders will not encode it, setting it to `null` instead in the payload
- Object types that don't specify any properties are treated as a `Dict(String,String)` 

Additional type definitions and encoders / decoders are generated, 
for any enumerable property in the protocol, as well as the return values of commands.  
These special type definitions are marked with a comment to indicate 
the fact that they are not part of the protocol spec, but rather generated dynamically to support the bindings.


## Commands

A function is generated for each command, named after the command (in snake case).  
The function handles both encoding the parameters to sent to the browser via the protocol, and decoding the response.
A `ProtocolError` error is returned if the decoding fails, this would mean there is a bug in the protocol
or the generated bindings.

The first parameter to the command function is always a `callback` of the form

```gleam
fn(method: String, parameters: Option(Json)) -> Result(Dynamic, RequestError)
```

By using this callback you can take advantage of the generated protocol encoders/decoders 
while also passing in your browser subject to direct the command to, and passing along additional
arguments, like the `sessionId` which is required for some operations.


## Events

Events are not implemented yet!


"

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
    // if the type is in the same domain, the domain name is omitted
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
  // It's for hinting at the command being implemented in another domain (I think?)
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
  let protocol =
    merge_protocols(browser_protocol, js_protocol)
    |> apply_protocol_patches()
  io.println(
    "Browser protocol version: "
    <> protocol.version.major
    <> "."
    <> protocol.version.minor,
  )
  print_protocol_stats(protocol)
  let stable_protocol = get_stable_protocol(protocol, False, False)
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

fn get_stable_inner_type(inner_type: Type, allow_experimental, allow_deprecated) {
  case inner_type {
    ObjectType(properties: Some(property_definitions)) -> {
      ObjectType(properties: {
        Some(
          list.filter_map(property_definitions, fn(inner_propdef) {
            get_stable_propdef(
              inner_propdef,
              allow_experimental,
              allow_deprecated,
            )
          }),
        )
      })
    }
    _ -> inner_type
  }
}

fn get_stable_propdef(
  propdef: PropertyDefinition,
  allow_experimental,
  allow_deprecated,
) -> Result(PropertyDefinition, Nil) {
  case
    is_allowed(propdef.experimental, allow_experimental)
    && is_allowed(propdef.deprecated, allow_deprecated)
  {
    True ->
      Ok(PropertyDefinition(
        name: propdef.name,
        description: propdef.description,
        experimental: propdef.experimental,
        deprecated: propdef.deprecated,
        optional: propdef.optional,
        inner: get_stable_inner_type(
          propdef.inner,
          allow_experimental,
          allow_deprecated,
        ),
      ))
    False -> Error(Nil)
  }
}

fn get_stable_event(
  event: Event,
  allow_experimental,
  allow_deprecated,
) -> Result(Event, Nil) {
  case
    is_allowed(event.experimental, allow_experimental)
    && is_allowed(event.deprecated, allow_deprecated)
  {
    True ->
      Ok(
        Event(
          name: event.name,
          description: event.description,
          experimental: event.experimental,
          deprecated: event.deprecated,
          parameters: {
            case event.parameters {
              Some(params) ->
                Some(
                  list.filter_map(params, fn(param) {
                    get_stable_propdef(
                      param,
                      allow_experimental,
                      allow_deprecated,
                    )
                  }),
                )
              None -> None
            }
          },
        ),
      )
    False -> Error(Nil)
  }
}

fn get_stable_command(
  command: Command,
  allow_experimental,
  allow_deprecated,
) -> Result(Command, Nil) {
  case
    is_allowed(command.experimental, allow_experimental)
    && is_allowed(command.deprecated, allow_deprecated)
  {
    True ->
      Ok(
        Command(
          name: command.name,
          description: command.description,
          experimental: command.experimental,
          deprecated: command.deprecated,
          parameters: {
            case command.parameters {
              Some(params) ->
                Some(
                  list.filter_map(params, fn(param) {
                    get_stable_propdef(
                      param,
                      allow_experimental,
                      allow_deprecated,
                    )
                  }),
                )
              None -> None
            }
          },
          returns: {
            case command.returns {
              Some(returns) ->
                Some(
                  list.filter_map(returns, fn(param) {
                    get_stable_propdef(
                      param,
                      allow_experimental,
                      allow_deprecated,
                    )
                  }),
                )
              None -> None
            }
          },
        ),
      )
    False -> Error(Nil)
  }
}

fn get_stable_type(
  param_type: TypeDefinition,
  allow_experimental,
  allow_deprecated,
) -> Result(TypeDefinition, Nil) {
  case
    is_allowed(param_type.experimental, allow_experimental)
    && is_allowed(param_type.deprecated, allow_deprecated)
  {
    True ->
      Ok(TypeDefinition(
        id: param_type.id,
        description: param_type.description,
        experimental: param_type.experimental,
        deprecated: param_type.deprecated,
        inner: get_stable_inner_type(
          param_type.inner,
          allow_experimental,
          allow_deprecated,
        ),
      ))
    False -> Error(Nil)
  }
}

/// Return the protocol with experimental and deprecated domains, types, commands, parameters and events removed.  
/// Note that this might leave some optional lists as empty if all items are experimental / deprecated.
pub fn get_stable_protocol(
  protocol: Protocol,
  allow_experimental: Bool,
  allow_deprecated: Bool,
) -> Protocol {
  Protocol(
    version: protocol.version,
    domains: list.filter_map(protocol.domains, fn(domain) {
      case
        is_allowed(domain.experimental, allow_experimental)
        && is_allowed(domain.deprecated, allow_deprecated)
      {
        True -> {
          Ok(Domain(
            domain: domain.domain,
            experimental: domain.experimental,
            deprecated: domain.deprecated,
            dependencies: domain.dependencies,
            types: {
              case domain.types {
                Some(types) ->
                  Some(
                    list.filter_map(types, fn(type_item) {
                      get_stable_type(
                        type_item,
                        allow_experimental,
                        allow_deprecated,
                      )
                    }),
                  )
                None -> None
              }
            },
            commands: list.filter_map(domain.commands, fn(cmd) {
              get_stable_command(cmd, allow_experimental, allow_deprecated)
            }),
            events: {
              case domain.events {
                Some(events) ->
                  Some(
                    list.filter_map(events, fn(e) {
                      get_stable_event(e, allow_experimental, allow_deprecated)
                    }),
                  )
                None -> None
              }
            },
            description: domain.description,
          ))
        }
        False -> Error(Nil)
      }
    }),
  )
}

/// See `apply_protocol_patches` for more info
fn apply_propdef_patches(
  propdef: PropertyDefinition,
  domain: Domain,
) -> PropertyDefinition {
  PropertyDefinition(
    name: propdef.name,
    description: propdef.description,
    experimental: propdef.experimental,
    deprecated: propdef.deprecated,
    optional: propdef.optional,
    inner: apply_type_patches(propdef.inner, domain),
  )
}

/// See `apply_protocol_patches` for more info
fn apply_type_patches(inner_type: Type, domain: Domain) -> Type {
  case inner_type {
    // These patches are all references to other domains, which are not declared as dependencies.
    // We can't declare them as dependencies because that would create a circular dependency.
    // So we replace the reference with the actual type from the other domain.
    RefType("Page.FrameId")
      if domain.domain == "DOM" || domain.domain == "Accessibility"
    -> {
      io.println(
        "[PATCHING PROTOCOL] Replacing instance of 'Page.FrameId' with its primitive type, because the domain is not a depencency of "
        <> domain.domain,
      )
      PrimitiveType("string")
    }
    RefType("Network.TimeSinceEpoch") if domain.domain == "Security"
      || domain.domain == "Accessibility" -> {
      io.println(
        "[PATCHING PROTOCOL] Replacing instance of 'Network.TimeSinceEpoch' with its primitive type, because the domain is not a depencency of "
        <> domain.domain,
      )
      PrimitiveType("number")
    }
    // This reference occurs in the stable protocol for example here:
    // https://chromedevtools.github.io/devtools-protocol/1-3/Target/#method-createBrowserContext
    // But the referenced type is an experimental one
    RefType("Browser.BrowserContextID") | RefType("BrowserContextID") -> {
      io.println(
        "[PATCHING PROTOCOL] Replacing instance of 'BrowserContextID' with its primitive type, because it is an experimental property referenced by a stable one",
      )
      PrimitiveType("string")
    }
    ArrayType(ReferenceItem("Browser.BrowserContextID")) if domain.domain
      == "Target" -> {
      io.println(
        "[PATCHING PROTOCOL] Replacing instance of 'BrowserContextID' (array) with its primitive type, because it is an experimental property referenced by a stable one",
      )
      ArrayType(PrimitiveItem("string"))
    }
    // Object recursion
    ObjectType(properties: Some(property_definitions)) -> {
      ObjectType(properties: {
        Some(
          list.map(property_definitions, fn(inner_propdef) {
            apply_propdef_patches(inner_propdef, domain)
          }),
        )
      })
    }
    // Check for type in the same domain with unnnecessary domain qualifier
    RefType(ref_target) -> {
      let parts = string.split(ref_target, ".")
      case parts {
        [ref_domain, ref_name] if ref_domain == domain.domain -> {
          io.println(
            "[PATCHING PROTOCOL] Modifying ref target '"
            <> ref_target
            <> "'' because it is in the '"
            <> domain.domain
            <> "'' domain and does not need the domain qualifier.",
          )
          RefType(ref_name)
        }
        _ -> inner_type
      }
    }
    _ -> inner_type
  }
}

/// Apply patches to the parsed protocol to make it possible to generate bindings
/// The patches are hardcoded into the called functions.
/// There will be note in the code where the patches are applied about what they do,
/// and each patch application logs a line about being applied.
pub fn apply_protocol_patches(protocol: Protocol) -> Protocol {
  Protocol(
    version: protocol.version,
    domains: list.map(protocol.domains, fn(domain) {
      Domain(
        domain: domain.domain,
        experimental: {
          case domain.domain {
            // Mark the tracing domain as experimental so it gets filtered out
            // It's not included in the stable protocol as listed in the CDP docs
            // and it's also not necessary as far as I can tell
            "Tracing" -> {
              io.println(
                "[PATCHING PROTOCOL] Marking 'Tracing' domain as experimental because it is not included in stable 1.3",
              )
              Some(True)
            }
            _ -> domain.experimental
          }
        },
        deprecated: domain.deprecated,
        dependencies: {
          case domain.domain, domain.dependencies {
            // IO domain references Runtime.RemoteObjectId but doesn't declare the dependency to Runtime
            "IO", None
            -> {
              io.println(
                "[PATCHING PROTOCOL] Adding 'Runtime' dependency to IO domain",
              )
              Some(["Runtime"])
            }
            _, _ -> domain.dependencies
          }
        },
        types: {
          case domain.types {
            Some(types) ->
              Some(
                list.map(types, fn(type_item) {
                  TypeDefinition(
                    id: type_item.id,
                    description: type_item.description,
                    experimental: type_item.experimental,
                    deprecated: type_item.deprecated,
                    inner: apply_type_patches(type_item.inner, domain),
                  )
                }),
              )
            None -> None
          }
        },
        commands: list.map(domain.commands, fn(command) {
          Command(
            name: command.name,
            description: command.description,
            deprecated: command.deprecated,
            experimental: command.experimental,
            parameters: {
              case command.parameters {
                Some(properties) ->
                  Some(
                    list.map(properties, fn(p) {
                      apply_propdef_patches(p, domain)
                    }),
                  )
                None -> None
              }
            },
            returns: {
              case command.returns {
                Some(properties) ->
                  Some(
                    list.map(properties, fn(p) {
                      apply_propdef_patches(p, domain)
                    }),
                  )
                None -> None
              }
            },
          )
        }),
        events: domain.events,
        description: domain.description,
      )
    }),
  )
}

// Return if a prop is allowed to be deprecated / expired
// given the rule predicate of value "is_allowed_true"
fn is_allowed(value: Option(Bool), rule: Bool) -> Bool {
  case value {
    // Not experimental or deprecated -> always allowed
    None -> True
    Some(False) -> True
    // Experimental / deprecated allowed if rule permits
    Some(True) if rule -> True
    Some(True) -> False
  }
}

pub fn merge_protocols(left: Protocol, right: Protocol) -> Protocol {
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

// Huge spaghetti mess downstairs, don't look please

fn append_optional(
  builder: sb.StringBuilder,
  val: Option(a),
  callback: fn(a) -> String,
) {
  case val {
    Some(a) -> sb.append(builder, callback(a))
    None -> builder
  }
}

fn resolve_ref(ref_value) {
  let parts = string.split(ref_value, ".")
  case parts {
    [domain, type_name] -> snake_case(domain) <> "." <> type_name
    _ -> {
      ref_value
    }
  }
}

/// Safe snake case conversion that doesn't conflict with reserved words
fn safe_snake_case(input: String) {
  let res = snake_case(input)
  case res {
    "type" -> "type_"
    _ -> res
  }
}

fn to_gleam_primitive(protocol_primitive: String) {
  case protocol_primitive {
    "number" -> "Float"
    "integer" -> "Int"
    "string" -> "String"
    "boolean" -> "Bool"
    "any" -> "dynamic.Dynamic"
    _ -> {
      io.debug(protocol_primitive)
      panic as "can't translate to gleam primitive"
    }
  }
}

fn to_gleam_primitive_function(protocol_primitive: String) {
  case protocol_primitive {
    "number" -> "float"
    "integer" -> "int"
    "string" -> "string"
    "boolean" -> "bool"
    "any" -> "dynamic"
    _ -> {
      io.debug(protocol_primitive)
      panic as "can't translate to gleam primitive function"
    }
  }
}

/// I'm so lost
fn is(value: Option(Bool)) {
  case value {
    Some(True) -> True
    _ -> False
  }
}

fn gen_preamble(protocol: Protocol) {
  "
// ---------------------------------------------------------------------------
// |  !!!!!!   This is an autogenerated file - Do not edit manually  !!!!!!  |
// | Run ` gleam run -m scripts/generate_protocol_bindings.sh` to regenerate.|  
// ---------------------------------------------------------------------------
//// > ⚙️  This module was generated from the Chrome DevTools Protocol version **" <> protocol.version.major <> "." <> protocol.version.minor <> "**\n"
}

fn gen_attached_comment(content: String) {
  "/// " <> string.replace(content, "\n", "\n/// ") <> "\n"
}

fn gen_module_comment(content: String) {
  "//// " <> string.replace(content, "\n", "\n//// ") <> "\n"
}

/// Generate the root module for the protocol bindings
/// This is just an entrypoint with some documentation, and the version number
pub fn gen_root_module(protocol: Protocol) {
  sb.new()
  |> sb.append(gen_preamble(protocol))
  |> sb.append(
    "//// For reference: [See the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/",
  )
  |> sb.append(protocol.version.major)
  |> sb.append("-")
  |> sb.append(protocol.version.minor)
  |> sb.append("/")
  |> sb.append(")\n\n")
  |> sb.append(gen_module_comment(root_module_comment))
  |> sb.append("const version_major = \"" <> protocol.version.major <> "\"\n")
  |> sb.append("const version_minor = \"" <> protocol.version.minor <> "\"\n\n")
  |> sb.append(gen_attached_comment(
    "Get the protocol version as a tuple of major and minor version",
  ))
  |> sb.append("pub fn version() { #(version_major, version_minor)}\n")
  |> sb.to_string()
}

fn multiline_module_comment(content: String) {
  string.replace(content, "\n", "\n//// ")
}

fn gen_imports(domain: Domain) {
  let domain_imports =
    option.unwrap(domain.dependencies, [])
    |> list.map(fn(dependency) {
      "import protocol/" <> snake_case(dependency) <> "\n"
    })

  [
    "import chrome\n",
    "import gleam/dict\n",
    "import gleam/list\n",
    "import gleam/dynamic\n",
    "import gleam/result\n",
    "import gleam/option\n",
    "import gleam/json\n",
    "import chrobot/internal/utils\n",
    ..domain_imports
  ]
  |> string.join("")
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
    "//// [📖   View this domain on the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/",
  )
  |> sb.append(protocol.version.major)
  |> sb.append("-")
  |> sb.append(protocol.version.minor)
  |> sb.append("/")
  |> sb.append(domain.domain)
  |> sb.append("/)\n\n")
  |> sb.append(gen_imports(domain))
  |> sb.append("\n\n")
}

// Returns the enum definition of the attribute
// And in case of an enum attribute, the definition of the enum type that 
// the attribute references
// otherwise an empty string ("")
fn gen_attribute(
  root_name: String,
  name: String,
  t: Type,
  optional: Bool,
  comment: String,
) -> #(String, String) {
  let #(attr_value, enum_def) = case t {
    PrimitiveType(type_name) -> {
      #(to_gleam_primitive(type_name), "")
    }
    ArrayType(items: PrimitiveItem(type_name)) -> {
      #("List(" <> to_gleam_primitive(type_name) <> ")", "")
    }
    ArrayType(items: ReferenceItem(ref_target)) -> {
      #("List(" <> resolve_ref(ref_target) <> ")", "")
    }
    RefType(ref_target) -> {
      #(resolve_ref(ref_target), "")
    }
    EnumType(enum) -> {
      let enum_type_name = pascal_case(root_name) <> pascal_case(name)
      let enum_type_def =
        gen_attached_comment(
          "This type is not part of the protocol spec, it has been generated dynamically 
to represent the possible values of the enum property `"
          <> name
          <> "` of `"
          <> root_name
          <> "`",
        )
        <> "\npub type "
        <> enum_type_name
        <> "{"
        <> {
          enum
          |> list.map(fn(item) { enum_type_name <> pascal_case(item) <> "\n" })
          |> string.join("")
        }
        <> "}\n"
        <> gen_enum_encoder(enum_type_name, enum)
        <> "\n"
        <> gen_enum_decoder(enum_type_name, enum)
        <> "\n"
      #(enum_type_name, enum_type_def)
      // generate enum definition and ref
    }
    ObjectType(None) -> {
      #("dict.Dict(String,String)", "")
    }
    ObjectType(Some(_)) -> {
      io.debug(#(root_name, name, t, optional))
      panic as "Tried to generate an attribute from unsupported type (Object with properties)"
    }
  }

  let attached_comment = case comment {
    "" -> ""
    value -> "\n" <> gen_attached_comment(value <> "  ")
  }

  let attr_value = case optional {
    True -> "option.Option(" <> attr_value <> ")"
    False -> attr_value
  }

  #(
    attached_comment <> safe_snake_case(name) <> ": " <> attr_value <> ",\n",
    enum_def,
  )
}

// Returns the type definition body and any additional definitions required for
// this type as the second element in the tuple
fn gen_type_body(name: String, t: Type) -> #(String, String) {
  case t {
    PrimitiveType(type_name) -> {
      #(name <> "(" <> to_gleam_primitive(type_name) <> ")\n", "")
    }
    EnumType(enum) -> {
      #(
        enum
          |> list.map(fn(item) { name <> pascal_case(item) <> "\n" })
          |> string.join(""),
        "",
      )
    }
    ArrayType(items: PrimitiveItem(type_name)) -> {
      #(name <> "(List(" <> to_gleam_primitive(type_name) <> "))\n", "")
    }
    ArrayType(items: ReferenceItem(ref_target)) -> {
      #(name <> "(List(" <> resolve_ref(ref_target) <> "))\n", "")
    }
    RefType(ref_target) -> {
      #(name <> "(" <> resolve_ref(ref_target) <> ")\n", "")
    }
    ObjectType(Some(properties)) -> {
      let attribute_gen_results =
        properties
        |> list.map(fn(prop) {
          gen_attribute(
            name,
            prop.name,
            prop.inner,
            is(prop.optional),
            option.unwrap(prop.description, ""),
          )
        })

      let #(attributes, enum_defs) = list.unzip(attribute_gen_results)

      #(
        name <> " (\n" <> string.join(attributes, "") <> ")\n",
        string.join(enum_defs, ""),
      )
    }
    ObjectType(None) -> {
      #(name <> "(dict.Dict(String,String))\n", "")
    }
  }
}

fn gen_type_def_body(builder: sb.StringBuilder, t: TypeDefinition) {
  let #(body, appendage) = gen_type_body(t.id, t.inner)
  builder
  |> append_optional(t.description, gen_attached_comment)
  // ID is already PascalCase!
  |> sb.append("pub type ")
  |> sb.append(t.id)
  |> sb.append("{\n")
  |> sb.append(body)
  |> sb.append("}\n\n")
  |> sb.append(appendage)
  |> sb.append("\n")
}

fn gen_type_def(builder: sb.StringBuilder, t: TypeDefinition) {
  gen_type_def_body(builder, t)
  |> sb.append(gen_type_def_encoder(t))
  |> sb.append(gen_type_def_decoder(t))
}

fn gen_type_definitions(domain: Domain) -> sb.StringBuilder {
  option.unwrap(domain.types, [])
  |> list.fold(sb.new(), gen_type_def)
}

fn internal_fn(name: String, params: String, body: String) {
  "@internal\npub fn " <> name <> "(\n" <> params <> ") {\n" <> body <> "}\n"
}

fn get_internal_function_name(internal_descriptor: String, type_name: String) {
  case string.split(type_name, ".") {
    [val] -> internal_descriptor <> "__" <> snake_case(val)
    [domain, val] ->
      snake_case(domain)
      <> "."
      <> internal_descriptor
      <> "__"
      <> snake_case(val)
    _ -> {
      io.debug(#(internal_descriptor, type_name))
      panic as "Can't get internal name from passed type_name"
    }
  }
}

fn get_encoder_name(type_name: String) {
  get_internal_function_name("encode", type_name)
}

fn get_decoder_name(type_name: String) {
  get_internal_function_name("decode", type_name)
}

pub fn gen_enum_encoder(enum_type_name: String, enum: List(String)) {
  get_encoder_name(enum_type_name)
  |> internal_fn(
    "value__: " <> enum_type_name <> "\n",
    "case value__{\n"
      <> list.fold(enum, "", fn(acc, current) {
      acc
      <> enum_type_name
      <> pascal_case(current)
      <> " -> \""
      <> current
      <> "\"\n"
    })
      <> "}\n|> json.string()\n",
  )
}

pub fn gen_enum_decoder(enum_type_name: String, enum: List(String)) {
  get_decoder_name(enum_type_name)
  |> internal_fn(
    "value__: dynamic.Dynamic\n",
    "case dynamic.string(value__){\n"
      <> list.fold(enum, "", fn(acc, current) {
      acc
      <> "Ok(\""
      <> current
      <> "\") -> Ok("
      <> enum_type_name
      <> pascal_case(current)
      <> ")\n"
    })
      <> "Error(error) -> Error(error)\nOk(other) -> Error([dynamic.DecodeError(expected: \"valid enum property\", found:other, path: [\"enum decoder\"])])"
      <> "}\n",
  )
}

/// Context: https://github.com/gleam-lang/json?tab=readme-ov-file#encoding
/// Given the value_name "value.lives" 
/// and its corresponding type PrimitiveType("int")
/// it should output: `json.int(value.lives))`
/// The root name and attribute name are just there to construct the function name of Enum encoders
fn gen_property_encoder(
  root_name: String,
  attribute_name: String,
  value_name: String,
  value_type: Type,
) {
  case value_type {
    PrimitiveType("any") -> {
      "utils.alert_encode_dynamic(" <> value_name <> ")"
    }
    PrimitiveType(type_name) -> {
      "json."
      <> to_gleam_primitive_function(type_name)
      <> "("
      <> value_name
      <> ")"
    }
    ArrayType(PrimitiveItem("any")) -> {
      "// dynamic values cannot be encoded!\n json.null()\n"
    }
    ArrayType(PrimitiveItem(type_name)) -> {
      "json.array("
      <> value_name
      <> ", of: json."
      <> to_gleam_primitive_function(type_name)
      <> ")"
    }
    ArrayType(ReferenceItem(ref_target)) -> {
      "json.array("
      <> value_name
      <> ", of: "
      <> get_encoder_name(ref_target)
      <> ")"
    }
    EnumType(_enum) -> {
      get_encoder_name(pascal_case(root_name) <> pascal_case(attribute_name))
      <> "("
      <> value_name
      <> ")"
    }
    RefType(ref_target) -> {
      get_encoder_name(ref_target) <> "(" <> value_name <> ")"
    }
    ObjectType(Some(_properties)) -> {
      io.debug(#(root_name, attribute_name, value_type))
      panic as "Attempting nested object encoder generation"
    }
    ObjectType(None) -> {
      "dict.to_list(" <> value_name <> ")
        |> list.map(fn(i) { #(i.0, json.string(i.1)) })
        |> json.object"
    }
  }
}

/// Generate an object property encoder tuple like:
/// #("name", string(cat.name)),
/// #("lives", int(cat.lives)),
/// -> Returned as element 0 of the tuple
/// 
/// OR for optional properties, a pipe to a function like this:
/// |> add_optional(cat.owner, fn(owner) { #("owner", json.string(owner)) })
/// -> Returned as element 1 of the tuple
/// 
/// The root name is just there to construct the function name of Enum encoders
/// value_accessor is the path prefix under which to access the property, for encoder functions
/// this is "value__." as the properties are all under the single parameter, for command functions
/// there is no accessor as the properties are passed directly as parameters to the function, so "" will be passed
/// 
/// The return tuple works lik
fn gen_object_property_encoder(
  root_name: String,
  prop_def: PropertyDefinition,
  value_accessor: String,
) {
  let attribute_name = safe_snake_case(prop_def.name)
  case prop_def.optional {
    option.Some(True) -> {
      let encoder =
        gen_property_encoder(
          root_name,
          attribute_name,
          "inner_value__",
          prop_def.inner,
        )
      let wrapped_encoder = "#(\"" <> prop_def.name <> "\", " <> encoder <> ")"
      #(
        "",
        "|> utils.add_optional("
          <> value_accessor
          <> attribute_name
          <> ", fn(inner_value__){"
          <> wrapped_encoder
          <> "})\n",
      )
    }
    _ -> {
      let encoder =
        gen_property_encoder(
          root_name,
          attribute_name,
          value_accessor <> attribute_name,
          prop_def.inner,
        )
      #("#(\"" <> prop_def.name <> "\", " <> encoder <> "),\n", "")
    }
  }
}

fn gen_type_def_encoder(type_def: TypeDefinition) {
  case type_def.inner {
    PrimitiveType(primitive_type) -> {
      get_encoder_name(type_def.id)
      |> internal_fn(
        "value__: " <> type_def.id <> "\n",
        "case value__{\n"
          <> type_def.id
          <> "(inner_value__) -> json."
          <> to_gleam_primitive_function(primitive_type)
          <> "(inner_value__)\n}",
      )
    }
    EnumType(enum) -> {
      gen_enum_encoder(type_def.id, enum)
    }
    ArrayType(items: PrimitiveItem(primitive_type)) -> {
      get_encoder_name(type_def.id)
      |> internal_fn(
        "value__: " <> type_def.id <> "\n",
        "case value__{\n"
          <> type_def.id
          <> "(inner_value__) -> json.array(inner_value__, of: json."
          <> to_gleam_primitive_function(primitive_type)
          <> ")\n}",
      )
    }
    ObjectType(Some(properties)) -> {
      let #(property_encoders, appendices) =
        list.map(properties, fn(p) {
          gen_object_property_encoder(type_def.id, p, "value__.")
        })
        |> list.unzip()

      get_encoder_name(type_def.id)
      |> internal_fn(
        "value__: " <> type_def.id <> "\n",
        "json.object([\n"
          <> string.join(property_encoders, "")
          <> "]"
          <> string.join(appendices, "")
          <> ")",
      )
    }
    ObjectType(None) -> {
      get_encoder_name(type_def.id)
      |> internal_fn(
        "value__: " <> type_def.id <> "\n",
        "case value__{\n" <> type_def.id <> "(inner_value__) -> 
      dict.to_list(inner_value__)
      |> list.map(fn(i) { #(i.0, json.string(i.1)) })
      |> json.object
 }         ",
      )
    }
    // Below are not implemented because they currently don't occur
    ArrayType(items: ReferenceItem(_ref_target)) -> {
      io.debug(type_def)
      panic as "tried to generate type def encoder for an array of refs"
    }
    RefType(_) -> {
      io.debug(type_def)
      panic as "tried to generate type def encoder for a type which is a ref!"
    }
  }
}

/// Generates a decoder function for a given value, wich can be called with the value
/// E.g. `dynamic.string`
fn gen_property_decoder(
  root_name: String,
  attribute_name: String,
  value_type: Type,
) {
  case value_type {
    PrimitiveType(type_name) -> {
      "dynamic." <> to_gleam_primitive_function(type_name)
    }
    ArrayType(PrimitiveItem(type_name)) -> {
      "dynamic.list(dynamic." <> to_gleam_primitive_function(type_name) <> ")"
    }
    ArrayType(ReferenceItem(ref_target)) -> {
      "dynamic.list(" <> get_decoder_name(ref_target) <> ")"
    }
    EnumType(_enum) -> {
      get_decoder_name(pascal_case(root_name) <> pascal_case(attribute_name))
    }
    RefType(ref_target) -> get_decoder_name(ref_target)
    ObjectType(Some(_properties)) -> {
      io.debug(#(root_name, attribute_name, value_type))
      panic as "Attempting nested object decoder generation"
    }
    ObjectType(None) -> {
      "dynamic.dict(dynamic.string, dynamic.string)"
    }
  }
}

/// Generate an object property encoder statement like:
/// gleam```
///   use width <- result.try(
///    dynamic.field("field", dynamic.int)(value__)
///  )
/// ```
/// This is to be inserted into the function body of an object decoder function
fn gen_object_property_decoder(root_name: String, prop_def: PropertyDefinition) {
  let base_decoder = case prop_def.optional {
    Some(True) -> "optional_field"
    _ -> "field"
  }
  "use "
  <> safe_snake_case(prop_def.name)
  <> " <- result.try(dynamic."
  <> base_decoder
  <> "(\""
  <> prop_def.name
  <> "\","
  <> gen_property_decoder(root_name, prop_def.name, prop_def.inner)
  <> ")(value__))\n"
}

fn gen_type_def_decoder(type_def: TypeDefinition) {
  case type_def.inner {
    PrimitiveType(primitive_type) -> {
      get_decoder_name(type_def.id)
      |> internal_fn(
        "value__: dynamic.Dynamic",
        "value__ |> dynamic.decode1("
          <> type_def.id
          <> ", dynamic."
          <> to_gleam_primitive_function(primitive_type)
          <> ")",
      )
    }
    EnumType(enum) -> {
      gen_enum_decoder(type_def.id, enum)
    }
    ArrayType(items: PrimitiveItem(primitive_type)) -> {
      get_decoder_name(type_def.id)
      |> internal_fn(
        "value__: dynamic.Dynamic",
        "value__ |> dynamic.decode1("
          <> type_def.id
          <> ", dynamic.list(dynamic."
          <> to_gleam_primitive_function(primitive_type)
          <> "))",
      )
    }
    ObjectType(Some(properties)) -> {
      let prop_encoder_lines =
        list.map(properties, fn(p) {
          gen_object_property_decoder(type_def.id, p)
        })
        |> string.join("")

      let return_statement =
        "Ok("
        <> type_def.id
        <> "(\n"
        <> {
          list.map(properties, fn(p) {
            safe_snake_case(p.name) <> ":" <> safe_snake_case(p.name) <> ",\n"
          })
          |> string.join("")
        }
        <> "))"

      get_decoder_name(type_def.id)
      |> internal_fn(
        "value__: dynamic.Dynamic",
        prop_encoder_lines <> "\n" <> return_statement,
      )
    }
    ObjectType(None) -> {
      get_decoder_name(type_def.id)
      |> internal_fn(
        "value__: dynamic.Dynamic",
        "value__ |> dynamic.decode1("
          <> type_def.id
          <> ", dynamic.dict(dynamic.string, dynamic.string))",
      )
    }
    // Below are not implemented because they currently don't occur
    ArrayType(items: ReferenceItem(_ref_target)) -> {
      io.debug(type_def)
      panic as "tried to generate type def encoder for an array of refs"
    }
    RefType(_) -> {
      io.debug(type_def)
      panic as "tried to generate type def encoder for a type which is a ref!"
    }
  }
}

fn gen_command_return_type(command: Command) {
  let builder = sb.new()
  case command.returns {
    Some([]) -> builder
    Some(return_properties) -> {
      let return_type_def =
        TypeDefinition(
          id: pascal_case(command.name) <> "Response",
          description: Some(
            "This type is not part of the protocol spec, it has been generated dynamically
to represent the response to the command `"
            <> snake_case(command.name)
            <> "`",
          ),
          experimental: None,
          deprecated: None,
          inner: ObjectType(properties: Some(return_properties)),
        )

      gen_type_def_body(builder, return_type_def)
      |> sb.append(gen_type_def_decoder(return_type_def))
    }
    None -> builder
  }
}

/// Generate command parameters and supporting definitions
fn gen_command_parameters(command: Command) {
  case command.parameters {
    Some(params) -> {
      let param_gen_results =
        list.map(params, fn(param) {
          gen_attribute(
            command.name,
            param.name,
            param.inner,
            is(param.optional),
            "",
          )
        })
      let #(param_definitions, extra_definitions) =
        list.unzip(param_gen_results)

      // Duplicate the param name to create a label
      let param_definitions =
        list.map(param_definitions, fn(d) {
          let assert Ok(#(parameter_name, _)) =
            list.pop(string.split(d, ":"), fn(_) { True })
          parameter_name <> " " <> d
        })

      #(string.join(param_definitions, ""), string.join(extra_definitions, ""))
    }
    None -> #("", "")
  }
}

fn gen_command_body(command: Command, domain: Domain) {
  let base_encoder_part = {
    case command.parameters {
      None | Some([]) -> {
        "callback__(\""
        <> domain.domain
        <> "."
        <> command.name
        <> "\", option.None,"
        <> ")\n"
      }

      Some(properties) -> {
        let #(property_encoders, appendices) =
          list.map(properties, fn(p) {
            gen_object_property_encoder(command.name, p, "")
          })
          |> list.unzip()
        "callback__(\""
        <> domain.domain
        <> "."
        <> command.name
        <> "\", option.Some(json.object(["
        <> string.join(property_encoders, "")
        <> "]"
        <> string.join(appendices, "")
        <> ")))\n"
      }
    }
  }

  let #(decoder_part, final_encoder_part) = {
    case command.returns {
      None | Some([]) -> #("", base_encoder_part <> "\n")
      Some(_) -> {
        #(
          "\n"
            <> get_decoder_name(pascal_case(command.name) <> "Response")
            <> "(result__)"
            <> "\n|> result.replace_error(chrome.ProtocolError)\n",
          "use result__ <- result.try(" <> base_encoder_part <> ")\n",
        )
      }
    }
  }

  final_encoder_part <> decoder_part
}

fn gen_property_list_doc(properties: List(PropertyDefinition)) {
  list.map(properties, fn(prop) {
    " - `"
    <> safe_snake_case(prop.name)
    <> "`"
    <> {
      case prop.description {
        None -> "\n"
        Some(description) -> " : " <> description <> "\n"
      }
    }
  })
  |> string.join("")
}

fn gen_command_parameter_docs(command: Command) {
  sb.new()
  |> append_optional(command.parameters, fn(_) { "\nParameters:  \n" })
  |> append_optional(command.parameters, fn(i) { gen_property_list_doc(i) })
  |> append_optional(command.parameters, fn(_) { "\nReturns:  \n" })
  |> append_optional(command.returns, fn(i) { gen_property_list_doc(i) })
  |> sb.to_string()
  |> gen_attached_comment()
}

fn gen_command_function(command: Command, domain: Domain) {
  let #(param_definition, appendage) = gen_command_parameters(command)
  sb.new()
  |> sb.append(
    gen_attached_comment(option.unwrap(
      command.description,
      "This generated protocol command has no description",
    )),
  )
  |> sb.append(gen_command_parameter_docs(command))
  |> sb.append("pub fn ")
  |> sb.append(safe_snake_case(command.name))
  |> sb.append("(\n")
  |> sb.append("callback__, \n")
  |> sb.append(param_definition)
  |> sb.append("){\n")
  |> sb.append(gen_command_body(command, domain))
  |> sb.append("\n}\n")
  |> sb.append(appendage)
  |> sb.append("\n")
}

fn gen_commands(domain: Domain) {
  sb.new()
  |> sb.append_builder(
    sb.concat(list.map(domain.commands, gen_command_return_type)),
  )
  |> sb.append_builder(
    sb.concat(
      list.map(domain.commands, fn(c) { gen_command_function(c, domain) }),
    ),
  )
}

/// The heuristic is very naive, given an import like
/// `import gleam/option`
/// if the generated code contains the string`option.`
/// the import is considered used.
/// This should be good enough for our codegen output though.
fn remove_import_if_unused(
  builder: sb.StringBuilder,
  full_string: String,
  import_name: String,
) -> sb.StringBuilder {
  let assert Ok(import_short_name) =
    string.split(import_name, "/")
    |> list.last
  let assert Ok(matcher) = regex.from_string(import_short_name <> "\\.\\S+")
  case regex.check(matcher, full_string) {
    False -> sb.replace(builder, "import " <> import_name <> "\n", "")
    True -> builder
  }
}

/// Remove unused imports from the generated code 
fn remove_unused_imports(builder: sb.StringBuilder) -> sb.StringBuilder {
  let full_string = sb.to_string(builder)
  string.split(full_string, "\n")
  |> list.filter_map(fn(line) {
    case string.starts_with(line, "import ") {
      True -> Ok(string.drop_left(line, 7))
      False -> Error(Nil)
    }
  })
  |> list.fold(builder, fn(acc, current) {
    remove_import_if_unused(acc, full_string, current)
  })
}

@internal
pub fn gen_domain_module(protocol: Protocol, domain: Domain) {
  sb.new()
  |> sb.append(gen_preamble(protocol))
  |> sb.append_builder(gen_domain_module_header(protocol, domain))
  |> sb.append_builder(gen_type_definitions(domain))
  |> sb.append_builder(gen_commands(domain))
  |> remove_unused_imports()
  |> sb.to_string()
}
