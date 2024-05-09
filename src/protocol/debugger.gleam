//// > ⚙️  This module was generated from the Chrome DevTools Protocol version **1.3**
//// ## Debugger Domain  
////
//// Debugger domain exposes JavaScript debugging capabilities. It allows setting and removing
//// breakpoints, stepping through execution, exploring stack traces, etc.  
////
//// [📖   View this domain on the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/1-3/Debugger/)

// ---------------------------------------------------------------------------
// |  !!!!!!   This is an autogenerated file - Do not edit manually  !!!!!!  |
// | Run ` gleam run -m scripts/generate_protocol_bindings.sh` to regenerate.|  
// ---------------------------------------------------------------------------

import chrome
import gleam/option
import protocol/runtime

/// Breakpoint identifier.
pub type BreakpointId {
  BreakpointId(String)
}

/// Call frame identifier.
pub type CallFrameId {
  CallFrameId(String)
}

/// Location in the source code.
pub type Location {
  Location(
    script_id: runtime.ScriptId,
    line_number: Int,
    column_number: option.Option(Int),
  )
}

/// JavaScript call frame. Array of call frames form the call stack.
pub type CallFrame {
  CallFrame(
    call_frame_id: CallFrameId,
    function_name: String,
    function_location: option.Option(Location),
    location: Location,
    scope_chain: List(Scope),
    this: runtime.RemoteObject,
    return_value: option.Option(runtime.RemoteObject),
  )
}

/// Scope description.
pub type Scope {
  Scope(
    type_: ScopeType,
    object: runtime.RemoteObject,
    name: option.Option(String),
    start_location: option.Option(Location),
    end_location: option.Option(Location),
  )
}

/// This type is not part of the protocol spec, it has been generated dynamically 
/// to represent the possible values of the enum property `type` of `Scope`
pub type ScopeType {
  ScopeTypeGlobal
  ScopeTypeLocal
  ScopeTypeWith
  ScopeTypeClosure
  ScopeTypeCatch
  ScopeTypeBlock
  ScopeTypeScript
  ScopeTypeEval
  ScopeTypeModule
  ScopeTypeWasmExpressionStack
}

@internal
pub fn encode__scope_type(value: ScopeType) {
  case value {
    ScopeTypeGlobal -> "global"
    ScopeTypeLocal -> "local"
    ScopeTypeWith -> "with"
    ScopeTypeClosure -> "closure"
    ScopeTypeCatch -> "catch"
    ScopeTypeBlock -> "block"
    ScopeTypeScript -> "script"
    ScopeTypeEval -> "eval"
    ScopeTypeModule -> "module"
    ScopeTypeWasmExpressionStack -> "wasm-expression-stack"
  }
}

@internal
pub fn decode__scope_type(value: String) {
  case value {
    "global" -> Ok(ScopeTypeGlobal)
    "local" -> Ok(ScopeTypeLocal)
    "with" -> Ok(ScopeTypeWith)
    "closure" -> Ok(ScopeTypeClosure)
    "catch" -> Ok(ScopeTypeCatch)
    "block" -> Ok(ScopeTypeBlock)
    "script" -> Ok(ScopeTypeScript)
    "eval" -> Ok(ScopeTypeEval)
    "module" -> Ok(ScopeTypeModule)
    "wasm-expression-stack" -> Ok(ScopeTypeWasmExpressionStack)
    _ -> Error(chrome.ProtocolError)
  }
}

/// Search match for resource.
pub type SearchMatch {
  SearchMatch(line_number: Float, line_content: String)
}

pub type BreakLocation {
  BreakLocation(
    script_id: runtime.ScriptId,
    line_number: Int,
    column_number: option.Option(Int),
    type_: option.Option(BreakLocationType),
  )
}

/// This type is not part of the protocol spec, it has been generated dynamically 
/// to represent the possible values of the enum property `type` of `BreakLocation`
pub type BreakLocationType {
  BreakLocationTypeDebuggerStatement
  BreakLocationTypeCall
  BreakLocationTypeReturn
}

@internal
pub fn encode__break_location_type(value: BreakLocationType) {
  case value {
    BreakLocationTypeDebuggerStatement -> "debuggerStatement"
    BreakLocationTypeCall -> "call"
    BreakLocationTypeReturn -> "return"
  }
}

@internal
pub fn decode__break_location_type(value: String) {
  case value {
    "debuggerStatement" -> Ok(BreakLocationTypeDebuggerStatement)
    "call" -> Ok(BreakLocationTypeCall)
    "return" -> Ok(BreakLocationTypeReturn)
    _ -> Error(chrome.ProtocolError)
  }
}

/// Enum of possible script languages.
pub type ScriptLanguage {
  ScriptLanguageJavaScript
  ScriptLanguageWebAssembly
}

/// Debug symbols available for a wasm script.
pub type DebugSymbols {
  DebugSymbols(type_: DebugSymbolsType, external_url: option.Option(String))
}

/// This type is not part of the protocol spec, it has been generated dynamically 
/// to represent the possible values of the enum property `type` of `DebugSymbols`
pub type DebugSymbolsType {
  DebugSymbolsTypeNone
  DebugSymbolsTypeSourceMap
  DebugSymbolsTypeEmbeddedDwarf
  DebugSymbolsTypeExternalDwarf
}

@internal
pub fn encode__debug_symbols_type(value: DebugSymbolsType) {
  case value {
    DebugSymbolsTypeNone -> "None"
    DebugSymbolsTypeSourceMap -> "SourceMap"
    DebugSymbolsTypeEmbeddedDwarf -> "EmbeddedDWARF"
    DebugSymbolsTypeExternalDwarf -> "ExternalDWARF"
  }
}

@internal
pub fn decode__debug_symbols_type(value: String) {
  case value {
    "None" -> Ok(DebugSymbolsTypeNone)
    "SourceMap" -> Ok(DebugSymbolsTypeSourceMap)
    "EmbeddedDWARF" -> Ok(DebugSymbolsTypeEmbeddedDwarf)
    "ExternalDWARF" -> Ok(DebugSymbolsTypeExternalDwarf)
    _ -> Error(chrome.ProtocolError)
  }
}
