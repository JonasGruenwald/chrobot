//// > ⚙️  This module was generated from the Chrome DevTools Protocol version **1.3**
//// ## Runtime Domain  
////
//// Runtime domain exposes JavaScript runtime by means of remote evaluation and mirror objects.
//// Evaluation results are returned as mirror object that expose object type, string representation
//// and unique identifier that can be used for further object reference. Original objects are
//// maintained in memory unless they are either explicitly released or are released along with the
//// other objects in their object group.  
////
//// [📖   View this domain on the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/1-3/Runtime/)

// ---------------------------------------------------------------------------
// |  !!!!!!   This is an autogenerated file - Do not edit manually  !!!!!!  |
// | Run ` gleam run -m scripts/generate_protocol_bindings.sh` to regenerate.|  
// ---------------------------------------------------------------------------

import gleam/dict
import gleam/dynamic
import gleam/option

/// Unique script identifier.
pub type ScriptId {
  ScriptId(String)
}

/// Represents options for serialization. Overrides `generatePreview` and `returnByValue`.
pub type SerializationOptions {
  SerializationOptions(
    serialization: SerializationOptionsSerialization,
    max_depth: option.Option(Int),
    additional_parameters: option.Option(dict.Dict(String, String)),
  )
}

/// This type is not part of the protocol spec, it has been generated dynamically 
/// to represent the possible values of the enum property `serialization` of `SerializationOptions`
pub type SerializationOptionsSerialization {
  SerializationOptionsSerializationDeep
  SerializationOptionsSerializationJson
  SerializationOptionsSerializationIdOnly
}

/// Represents deep serialized value.
pub type DeepSerializedValue {
  DeepSerializedValue(
    type_: DeepSerializedValueType,
    value: option.Option(dynamic.Dynamic),
    object_id: option.Option(String),
    weak_local_object_reference: option.Option(Int),
  )
}

/// This type is not part of the protocol spec, it has been generated dynamically 
/// to represent the possible values of the enum property `type` of `DeepSerializedValue`
pub type DeepSerializedValueType {
  DeepSerializedValueTypeUndefined
  DeepSerializedValueTypeNull
  DeepSerializedValueTypeString
  DeepSerializedValueTypeNumber
  DeepSerializedValueTypeBoolean
  DeepSerializedValueTypeBigint
  DeepSerializedValueTypeRegexp
  DeepSerializedValueTypeDate
  DeepSerializedValueTypeSymbol
  DeepSerializedValueTypeArray
  DeepSerializedValueTypeObject
  DeepSerializedValueTypeFunction
  DeepSerializedValueTypeMap
  DeepSerializedValueTypeSet
  DeepSerializedValueTypeWeakmap
  DeepSerializedValueTypeWeakset
  DeepSerializedValueTypeError
  DeepSerializedValueTypeProxy
  DeepSerializedValueTypePromise
  DeepSerializedValueTypeTypedarray
  DeepSerializedValueTypeArraybuffer
  DeepSerializedValueTypeNode
  DeepSerializedValueTypeWindow
  DeepSerializedValueTypeGenerator
}

/// Unique object identifier.
pub type RemoteObjectId {
  RemoteObjectId(String)
}

/// Primitive value which cannot be JSON-stringified. Includes values `-0`, `NaN`, `Infinity`,
/// `-Infinity`, and bigint literals.
pub type UnserializableValue {
  UnserializableValue(String)
}

/// Mirror object referencing original JavaScript object.
pub type RemoteObject {
  RemoteObject(
    type_: RemoteObjectType,
    subtype: option.Option(RemoteObjectSubtype),
    class_name: option.Option(String),
    value: option.Option(dynamic.Dynamic),
    unserializable_value: option.Option(UnserializableValue),
    description: option.Option(String),
    object_id: option.Option(RemoteObjectId),
  )
}

/// This type is not part of the protocol spec, it has been generated dynamically 
/// to represent the possible values of the enum property `type` of `RemoteObject`
pub type RemoteObjectType {
  RemoteObjectTypeObject
  RemoteObjectTypeFunction
  RemoteObjectTypeUndefined
  RemoteObjectTypeString
  RemoteObjectTypeNumber
  RemoteObjectTypeBoolean
  RemoteObjectTypeSymbol
  RemoteObjectTypeBigint
}

/// This type is not part of the protocol spec, it has been generated dynamically 
/// to represent the possible values of the enum property `subtype` of `RemoteObject`
pub type RemoteObjectSubtype {
  RemoteObjectSubtypeArray
  RemoteObjectSubtypeNull
  RemoteObjectSubtypeNode
  RemoteObjectSubtypeRegexp
  RemoteObjectSubtypeDate
  RemoteObjectSubtypeMap
  RemoteObjectSubtypeSet
  RemoteObjectSubtypeWeakmap
  RemoteObjectSubtypeWeakset
  RemoteObjectSubtypeIterator
  RemoteObjectSubtypeGenerator
  RemoteObjectSubtypeError
  RemoteObjectSubtypeProxy
  RemoteObjectSubtypePromise
  RemoteObjectSubtypeTypedarray
  RemoteObjectSubtypeArraybuffer
  RemoteObjectSubtypeDataview
  RemoteObjectSubtypeWebassemblymemory
  RemoteObjectSubtypeWasmvalue
}

/// Object property descriptor.
pub type PropertyDescriptor {
  PropertyDescriptor(
    name: String,
    value: option.Option(RemoteObject),
    writable: option.Option(Bool),
    get: option.Option(RemoteObject),
    set: option.Option(RemoteObject),
    configurable: Bool,
    enumerable: Bool,
    was_thrown: option.Option(Bool),
    is_own: option.Option(Bool),
    symbol: option.Option(RemoteObject),
  )
}

/// Object internal property descriptor. This property isn't normally visible in JavaScript code.
pub type InternalPropertyDescriptor {
  InternalPropertyDescriptor(name: String, value: option.Option(RemoteObject))
}

/// Represents function call argument. Either remote object id `objectId`, primitive `value`,
/// unserializable primitive value or neither of (for undefined) them should be specified.
pub type CallArgument {
  CallArgument(
    value: option.Option(dynamic.Dynamic),
    unserializable_value: option.Option(UnserializableValue),
    object_id: option.Option(RemoteObjectId),
  )
}

/// Id of an execution context.
pub type ExecutionContextId {
  ExecutionContextId(Int)
}

/// Description of an isolated world.
pub type ExecutionContextDescription {
  ExecutionContextDescription(
    id: ExecutionContextId,
    origin: String,
    name: String,
    aux_data: option.Option(dict.Dict(String, String)),
  )
}

/// Detailed information about exception (or error) that was thrown during script compilation or
/// execution.
pub type ExceptionDetails {
  ExceptionDetails(
    exception_id: Int,
    text: String,
    line_number: Int,
    column_number: Int,
    script_id: option.Option(ScriptId),
    url: option.Option(String),
    stack_trace: option.Option(StackTrace),
    exception: option.Option(RemoteObject),
    execution_context_id: option.Option(ExecutionContextId),
  )
}

/// Number of milliseconds since epoch.
pub type Timestamp {
  Timestamp(Float)
}

/// Number of milliseconds.
pub type TimeDelta {
  TimeDelta(Float)
}

/// Stack entry for runtime errors and assertions.
pub type CallFrame {
  CallFrame(
    function_name: String,
    script_id: ScriptId,
    url: String,
    line_number: Int,
    column_number: Int,
  )
}

/// Call frames for assertions or error messages.
pub type StackTrace {
  StackTrace(
    description: option.Option(String),
    call_frames: List(CallFrame),
    parent: option.Option(StackTrace),
  )
}
