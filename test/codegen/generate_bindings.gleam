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

import chrobot/internal/utils
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp
import gleam/string
import gleam/string_tree as st
import justin_fork.{pascal_case, snake_case}
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
  let target = "src/chrobot/protocol.gleam"
  io.println("Writing root protocol module to: " <> target)
  let assert Ok(_) = file.write(gen_root_module(stable_protocol), to: target)
  let assert Ok(_) = file.create_directory_all("src/protocol")
  list.each(stable_protocol.domains, fn(domain) {
    let target =
      "src/chrobot/protocol/" <> snake_case(domain.domain) <> ".gleam"
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
    RefType("Network.TimeSinceEpoch")
      if domain.domain == "Security" || domain.domain == "Accessibility"
    -> {
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
    ArrayType(ReferenceItem("Browser.BrowserContextID"))
      if domain.domain == "Target"
    -> {
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
            "IO", None -> {
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

fn parse_type_def_decoder() -> decode.Decoder(TypeDefinition) {
  use id <- decode.field("id", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )
  use experimental <- decode.optional_field(
    "experimental",
    None,
    decode.optional(decode.bool),
  )
  use deprecated <- decode.optional_field(
    "deprecated",
    None,
    decode.optional(decode.bool),
  )
  use inner <- decode.then(parse_type_decoder())
  decode.success(TypeDefinition(
    id:,
    description:,
    experimental:,
    deprecated:,
    inner:,
  ))
}

fn parse_property_def_decoder() -> decode.Decoder(PropertyDefinition) {
  use name <- decode.field("name", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )
  use experimental <- decode.optional_field(
    "experimental",
    None,
    decode.optional(decode.bool),
  )
  use deprecated <- decode.optional_field(
    "deprecated",
    None,
    decode.optional(decode.bool),
  )
  use optional <- decode.optional_field(
    "optional",
    None,
    decode.optional(decode.bool),
  )
  use inner <- decode.then(parse_type_decoder())
  decode.success(PropertyDefinition(
    name:,
    description:,
    experimental:,
    deprecated:,
    optional:,
    inner:,
  ))
}

/// For arrays we handle only primitive types or refs
fn parse_array_type_item_decoder() -> decode.Decoder(ArrayTypeItem) {
  use ref <- decode.optional_field("$ref", None, decode.optional(decode.string))
  use type_name <- decode.optional_field(
    "type",
    None,
    decode.optional(decode.string),
  )
  case ref, type_name {
    Some(ref_target), _ -> decode.success(ReferenceItem(ref_target))
    _, Some(type_name_val) -> decode.success(PrimitiveItem(type_name_val))
    None, None ->
      decode.failure(PrimitiveItem(""), "ArrayTypeItem with $ref or type")
  }
}

/// Parse a 'type' object from the protocol spec
/// This is also used to parse parameters and returns
/// Therefore it also parses and returns '$ref' types
/// which are not present in the top-level 'types' field
fn parse_type_decoder() -> decode.Decoder(Type) {
  use type_name <- decode.optional_field(
    "type",
    None,
    decode.optional(decode.string),
  )
  use enum <- decode.optional_field(
    "enum",
    None,
    decode.optional(decode.list(decode.string)),
  )
  use ref <- decode.optional_field("$ref", None, decode.optional(decode.string))
  use properties <- decode.optional_field(
    "properties",
    None,
    decode.optional(decode.list(parse_property_def_decoder())),
  )
  use items <- decode.optional_field(
    "items",
    None,
    decode.optional(parse_array_type_item_decoder()),
  )
  case type_name, enum, ref, properties, items {
    Some("string"), Some(enum_values), _, _, _ ->
      decode.success(EnumType(enum_values))
    Some("string"), None, _, _, _
    | Some("boolean"), _, _, _, _
    | Some("number"), _, _, _, _
    | Some("any"), _, _, _, _
    | Some("integer"), _, _, _, _
    -> {
      case type_name {
        Some(name) -> decode.success(PrimitiveType(name))
      }
    }
    Some("object"), _, _, props, _ -> decode.success(ObjectType(props))
    Some("array"), _, _, _, Some(item) -> decode.success(ArrayType(item))
    _, _, Some(ref_target), _, _ -> decode.success(RefType(ref_target))
    Some(_), _, _, _, _ | None, _, _, _, _ ->
      decode.failure(PrimitiveType(""), "A valid type")
  }
}

pub fn parse_protocol(path from: String) -> Result(Protocol, json.DecodeError) {
  let assert Ok(json_string) = file.read(from: from)

  let command_decoder = {
    use name <- decode.field("name", decode.string)
    use description <- decode.optional_field(
      "description",
      None,
      decode.optional(decode.string),
    )
    use experimental <- decode.optional_field(
      "experimental",
      None,
      decode.optional(decode.bool),
    )
    use deprecated <- decode.optional_field(
      "deprecated",
      None,
      decode.optional(decode.bool),
    )
    use parameters <- decode.optional_field(
      "parameters",
      None,
      decode.optional(decode.list(parse_property_def_decoder())),
    )
    use returns <- decode.optional_field(
      "returns",
      None,
      decode.optional(decode.list(parse_property_def_decoder())),
    )
    decode.success(Command(
      name:,
      description:,
      experimental:,
      deprecated:,
      parameters:,
      returns:,
    ))
  }

  let event_decoder = {
    use name <- decode.field("name", decode.string)
    use description <- decode.optional_field(
      "description",
      None,
      decode.optional(decode.string),
    )
    use experimental <- decode.optional_field(
      "experimental",
      None,
      decode.optional(decode.bool),
    )
    use deprecated <- decode.optional_field(
      "deprecated",
      None,
      decode.optional(decode.bool),
    )
    use parameters <- decode.optional_field(
      "parameters",
      None,
      decode.optional(decode.list(parse_property_def_decoder())),
    )
    decode.success(Event(
      name:,
      description:,
      experimental:,
      deprecated:,
      parameters:,
    ))
  }

  let domain_decoder = {
    use domain <- decode.field("domain", decode.string)
    use experimental <- decode.optional_field(
      "experimental",
      None,
      decode.optional(decode.bool),
    )
    use deprecated <- decode.optional_field(
      "deprecated",
      None,
      decode.optional(decode.bool),
    )
    use dependencies <- decode.optional_field(
      "dependencies",
      None,
      decode.optional(decode.list(decode.string)),
    )
    use types <- decode.optional_field(
      "types",
      None,
      decode.optional(decode.list(parse_type_def_decoder())),
    )
    use commands <- decode.field("commands", decode.list(command_decoder))
    use events <- decode.optional_field(
      "events",
      None,
      decode.optional(decode.list(event_decoder)),
    )
    use description <- decode.optional_field(
      "description",
      None,
      decode.optional(decode.string),
    )
    decode.success(Domain(
      domain:,
      experimental:,
      deprecated:,
      dependencies:,
      types:,
      commands:,
      events:,
      description:,
    ))
  }

  let version_decoder = {
    use major <- decode.field("major", decode.string)
    use minor <- decode.field("minor", decode.string)
    decode.success(Version(major:, minor:))
  }

  let protocol_decoder = {
    use version <- decode.field("version", version_decoder)
    use domains <- decode.field("domains", decode.list(domain_decoder))
    decode.success(Protocol(version:, domains:))
  }

  json.parse(from: json_string, using: protocol_decoder)
}

// --- CODEGEN ---

// Huge spaghetti mess downstairs, don't look please

fn append_optional(
  builder: st.StringTree,
  val: Option(a),
  callback: fn(a) -> String,
) {
  case val {
    Some(a) -> st.append(builder, callback(a))
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
      echo protocol_primitive
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
      echo protocol_primitive
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
// |                     Run `codegen.sh` to regenerate.                     |
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
  st.new()
  |> st.append(gen_preamble(protocol))
  |> st.append(
    "//// For reference: [See the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/",
  )
  |> st.append(protocol.version.major)
  |> st.append("-")
  |> st.append(protocol.version.minor)
  |> st.append("/")
  |> st.append(")\n\n")
  |> st.append(gen_module_comment(root_module_comment))
  |> st.append("const version_major = \"" <> protocol.version.major <> "\"\n")
  |> st.append("const version_minor = \"" <> protocol.version.minor <> "\"\n\n")
  |> st.append(gen_attached_comment(
    "Get the protocol version as a tuple of major and minor version",
  ))
  |> st.append("pub fn version() { #(version_major, version_minor)}\n")
  |> st.to_string()
}

fn multiline_module_comment(content: String) {
  string.replace(content, "\n", "\n//// ")
}

fn gen_imports(domain: Domain) {
  let domain_imports =
    option.unwrap(domain.dependencies, [])
    |> list.map(fn(dependency) {
      "import chrobot/protocol/" <> snake_case(dependency) <> "\n"
    })

  [
    "import chrobot/chrome\n",
    "import gleam/dict\n",
    "import gleam/dynamic\n",
    "import gleam/dynamic/decode\n",
    "import gleam/json\n",
    "import gleam/list\n",
    "import gleam/option\n",
    "import gleam/result\n",
    "import chrobot/internal/utils\n",
    ..domain_imports
  ]
  |> string.join("")
}

fn gen_domain_module_header(protocol: Protocol, domain: Domain) {
  st.new()
  |> st.append("//// ## " <> domain.domain <> " Domain")
  |> st.append("  \n////\n")
  |> st.append("//// ")
  |> st.append(
    option.unwrap(
      domain.description,
      "This protocol domain has no description.",
    )
    |> multiline_module_comment(),
  )
  |> st.append("  \n////\n")
  |> st.append(
    "//// [📖   View this domain on the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/",
  )
  |> st.append(protocol.version.major)
  |> st.append("-")
  |> st.append(protocol.version.minor)
  |> st.append("/")
  |> st.append(domain.domain)
  |> st.append("/)\n\n")
  |> st.append(gen_imports(domain))
  |> st.append("\n\n")
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
      echo #(root_name, name, t, optional)
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

fn gen_type_def_body(builder: st.StringTree, t: TypeDefinition) {
  let #(body, appendage) = gen_type_body(t.id, t.inner)
  builder
  |> append_optional(t.description, gen_attached_comment)
  // ID is already PascalCase!
  |> st.append("pub type ")
  |> st.append(t.id)
  |> st.append("{\n")
  |> st.append(body)
  |> st.append("}\n\n")
  |> st.append(appendage)
  |> st.append("\n")
}

fn gen_type_def(builder: st.StringTree, t: TypeDefinition) {
  gen_type_def_body(builder, t)
  |> st.append(gen_type_def_encoder(t))
  |> st.append(gen_type_def_decoder(t))
}

fn gen_type_definitions(domain: Domain) -> st.StringTree {
  option.unwrap(domain.types, [])
  |> list.fold(st.new(), gen_type_def)
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
      echo #(internal_descriptor, type_name)
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
  // Get the first variant for use in failure case
  let first_variant = case list.first(enum) {
    Ok(v) -> pascal_case(v)
    Error(_) -> ""
  }

  get_decoder_name(enum_type_name)
  |> internal_fn(
    "",
    "{\nuse value__ <- decode.then(decode.string)\ncase value__ {\n"
      <> list.fold(enum, "", fn(acc, current) {
      acc
      <> "\""
      <> current
      <> "\" -> decode.success("
      <> enum_type_name
      <> pascal_case(current)
      <> ")\n"
    })
      <> "_ -> decode.failure("
      <> enum_type_name
      <> first_variant
      <> ", \"valid enum property\")\n}\n}",
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
      echo #(root_name, attribute_name, value_type)
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
      echo type_def
      panic as "tried to generate type def encoder for an array of refs"
    }
    RefType(_) -> {
      echo type_def
      panic as "tried to generate type def encoder for a type which is a ref!"
    }
  }
}

/// Generates a decoder expression that returns a Decoder(T)
/// E.g. `decode.string`
fn gen_property_decoder(
  root_name: String,
  attribute_name: String,
  value_type: Type,
) {
  case value_type {
    PrimitiveType(type_name) -> {
      "decode." <> to_gleam_primitive_function(type_name)
    }
    ArrayType(PrimitiveItem(type_name)) -> {
      "decode.list(decode." <> to_gleam_primitive_function(type_name) <> ")"
    }
    ArrayType(ReferenceItem(ref_target)) -> {
      "decode.list(" <> get_decoder_name(ref_target) <> "())"
    }
    EnumType(_enum) -> {
      get_decoder_name(pascal_case(root_name) <> pascal_case(attribute_name))
      <> "()"
    }
    RefType(ref_target) -> get_decoder_name(ref_target) <> "()"
    ObjectType(Some(_properties)) -> {
      echo #(root_name, attribute_name, value_type)
      panic as "Attempting nested object decoder generation"
    }
    ObjectType(None) -> {
      "decode.dict(decode.string, decode.string)"
    }
  }
}

/// Generate an object property decoder statement like:
/// gleam```
///   use width <- decode.field("field", decode.int)
/// ```
/// This is to be inserted into the function body of an object decoder function
fn gen_object_property_decoder(root_name: String, prop_def: PropertyDefinition) {
  let inner_decoder =
    gen_property_decoder(root_name, prop_def.name, prop_def.inner)
  case prop_def.optional, prop_def.inner {
    // Special case: optional dynamic fields need to preserve null vs missing
    // Using decode.map(option.Some) ensures null becomes Some(dynamic_nil)
    // rather than None (which would be indistinguishable from missing field)
    Some(True), PrimitiveType("any") ->
      "use "
      <> safe_snake_case(prop_def.name)
      <> " <- decode.optional_field(\""
      <> prop_def.name
      <> "\", option.None, "
      <> inner_decoder
      <> " |> decode.map(option.Some))\n"
    Some(True), _ ->
      "use "
      <> safe_snake_case(prop_def.name)
      <> " <- decode.optional_field(\""
      <> prop_def.name
      <> "\", option.None, decode.optional("
      <> inner_decoder
      <> "))\n"
    _, _ ->
      "use "
      <> safe_snake_case(prop_def.name)
      <> " <- decode.field(\""
      <> prop_def.name
      <> "\", "
      <> inner_decoder
      <> ")\n"
  }
}

fn gen_type_def_decoder(type_def: TypeDefinition) {
  case type_def.inner {
    PrimitiveType(primitive_type) -> {
      get_decoder_name(type_def.id)
      |> internal_fn(
        "",
        "{\nuse value__ <- decode.then(decode."
          <> to_gleam_primitive_function(primitive_type)
          <> ")\ndecode.success("
          <> type_def.id
          <> "(value__))\n}",
      )
    }
    EnumType(enum) -> {
      gen_enum_decoder(type_def.id, enum)
    }
    ArrayType(items: PrimitiveItem(primitive_type)) -> {
      get_decoder_name(type_def.id)
      |> internal_fn(
        "",
        "{\nuse value__ <- decode.then(decode.list(decode."
          <> to_gleam_primitive_function(primitive_type)
          <> "))\ndecode.success("
          <> type_def.id
          <> "(value__))\n}",
      )
    }
    ObjectType(Some(properties)) -> {
      let prop_decoder_lines =
        list.map(properties, fn(p) {
          gen_object_property_decoder(type_def.id, p)
        })
        |> string.join("")

      let return_statement =
        "decode.success("
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
        "",
        "{\n" <> prop_decoder_lines <> "\n" <> return_statement <> "\n}",
      )
    }
    ObjectType(None) -> {
      get_decoder_name(type_def.id)
      |> internal_fn(
        "",
        "{\nuse value__ <- decode.then(decode.dict(decode.string, decode.string))\ndecode.success("
          <> type_def.id
          <> "(value__))\n}",
      )
    }
    // Below are not implemented because they currently don't occur
    ArrayType(items: ReferenceItem(_ref_target)) -> {
      echo type_def
      panic as "tried to generate type def encoder for an array of refs"
    }
    RefType(_) -> {
      echo type_def
      panic as "tried to generate type def encoder for a type which is a ref!"
    }
  }
}

fn gen_command_return_type(command: Command) {
  let builder = st.new()
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
      |> st.append(gen_type_def_decoder(return_type_def))
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
            utils.find_remove(string.split(d, ":"), fn(_) { True })
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
          "\ndecode.run(result__, "
            <> get_decoder_name(pascal_case(command.name) <> "Response")
            <> "())"
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
  st.new()
  |> append_optional(command.parameters, fn(_) { "\nParameters:  \n" })
  |> append_optional(command.parameters, fn(i) { gen_property_list_doc(i) })
  |> append_optional(command.parameters, fn(_) { "\nReturns:  \n" })
  |> append_optional(command.returns, fn(i) { gen_property_list_doc(i) })
  |> st.to_string()
  |> gen_attached_comment()
}

fn gen_command_function(command: Command, domain: Domain) {
  let #(param_definition, appendage) = gen_command_parameters(command)
  st.new()
  |> st.append(
    gen_attached_comment(option.unwrap(
      command.description,
      "This generated protocol command has no description",
    )),
  )
  |> st.append(gen_command_parameter_docs(command))
  |> st.append("pub fn ")
  |> st.append(safe_snake_case(command.name))
  |> st.append("(\n")
  |> st.append("callback__, \n")
  |> st.append(param_definition)
  |> st.append("){\n")
  |> st.append(gen_command_body(command, domain))
  |> st.append("\n}\n")
  |> st.append(appendage)
  |> st.append("\n")
}

fn gen_commands(domain: Domain) {
  st.new()
  |> st.append_tree(
    st.concat(list.map(domain.commands, gen_command_return_type)),
  )
  |> st.append_tree(
    st.concat(
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
  builder: st.StringTree,
  full_string: String,
  import_name: String,
) -> st.StringTree {
  let assert Ok(import_short_name) =
    string.split(import_name, "/")
    |> list.last
  let assert Ok(matcher) = regexp.from_string(import_short_name <> "\\.\\S+")
  case regexp.check(matcher, full_string) {
    False -> st.replace(builder, "import " <> import_name <> "\n", "")
    True -> builder
  }
}

/// Remove unused imports from the generated code
fn remove_unused_imports(builder: st.StringTree) -> st.StringTree {
  let full_string = st.to_string(builder)
  string.split(full_string, "\n")
  |> list.filter_map(fn(line) {
    case string.starts_with(line, "import ") {
      True -> Ok(string.drop_start(line, 7))
      False -> Error(Nil)
    }
  })
  |> list.fold(builder, fn(acc, current) {
    remove_import_if_unused(acc, full_string, current)
  })
}

@internal
pub fn gen_domain_module(protocol: Protocol, domain: Domain) {
  st.new()
  |> st.append(gen_preamble(protocol))
  |> st.append_tree(gen_domain_module_header(protocol, domain))
  |> st.append_tree(gen_type_definitions(domain))
  |> st.append_tree(gen_commands(domain))
  |> remove_unused_imports()
  |> st.to_string()
}
