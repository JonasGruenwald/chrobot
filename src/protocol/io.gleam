//// > ⚙️  This module was generated from the Chrome DevTools Protocol version **1.3**
//// ## IO Domain  
////
//// Input/Output operations for streams produced by DevTools.  
////
//// [📖   View this domain on the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/1-3/IO/)

// ---------------------------------------------------------------------------
// |  !!!!!!   This is an autogenerated file - Do not edit manually  !!!!!!  |
// | Run ` gleam run -m scripts/generate_protocol_bindings.sh` to regenerate.|  
// ---------------------------------------------------------------------------

import chrobot/internal/utils
import chrome
import gleam/dynamic
import gleam/json
import gleam/option
import gleam/result
import protocol/runtime

/// This is either obtained from another method or specified as `blob:<uuid>` where
/// `<uuid>` is an UUID of a Blob.
pub type StreamHandle {
  StreamHandle(String)
}

@internal
pub fn encode__stream_handle(value__: StreamHandle) {
  case value__ {
    StreamHandle(inner_value__) -> json.string(inner_value__)
  }
}

@internal
pub fn decode__stream_handle(value__: dynamic.Dynamic) {
  value__
  |> dynamic.decode1(StreamHandle, dynamic.string)
}

/// This type is not part of the protocol spec, it has been generated dynamically
/// to represent the response to the command `read`
pub type ReadResponse {
  ReadResponse(
    base64_encoded: option.Option(Bool),
    /// Set if the data is base64-encoded
    /// 
    data: String,
    /// Data that were read.
    /// 
    eof: Bool,
  )
}

/// Set if the end-of-file condition occurred while reading.
/// 
@internal
pub fn decode__read_response(value__: dynamic.Dynamic) {
  use base64_encoded <- result.try(dynamic.optional_field(
    "base64Encoded",
    dynamic.bool,
  )(value__))
  use data <- result.try(dynamic.field("data", dynamic.string)(value__))
  use eof <- result.try(dynamic.field("eof", dynamic.bool)(value__))

  Ok(ReadResponse(base64_encoded: base64_encoded, data: data, eof: eof))
}

/// This type is not part of the protocol spec, it has been generated dynamically
/// to represent the response to the command `resolve_blob`
pub type ResolveBlobResponse {
  ResolveBlobResponse(uuid: String)
}

/// UUID of the specified Blob.
/// 
@internal
pub fn decode__resolve_blob_response(value__: dynamic.Dynamic) {
  use uuid <- result.try(dynamic.field("uuid", dynamic.string)(value__))

  Ok(ResolveBlobResponse(uuid: uuid))
}

/// Close the stream, discard any temporary backing storage.
/// 
/// Parameters:  
///  - `handle` : Handle of the stream to close.
/// 
/// Returns:  
/// 
pub fn close(callback__, handle handle: StreamHandle) {
  callback__(
    "IO.close",
    option.Some(json.object([#("handle", encode__stream_handle(handle))])),
  )
}

/// Read a chunk of the stream
/// 
/// Parameters:  
///  - `handle` : Handle of the stream to read.
///  - `offset` : Seek to the specified offset before reading (if not specified, proceed with offset
/// following the last read). Some types of streams may only support sequential reads.
///  - `size` : Maximum number of bytes to read (left upon the agent discretion if not specified).
/// 
/// Returns:  
///  - `base64_encoded` : Set if the data is base64-encoded
///  - `data` : Data that were read.
///  - `eof` : Set if the end-of-file condition occurred while reading.
/// 
pub fn read(
  callback__,
  handle handle: StreamHandle,
  offset offset: option.Option(Int),
  size size: option.Option(Int),
) {
  use result__ <- result.try(callback__(
    "IO.read",
    option.Some(json.object(
      [#("handle", encode__stream_handle(handle))]
      |> utils.add_optional(offset, fn(inner_value__) {
        #("offset", json.int(inner_value__))
      })
      |> utils.add_optional(size, fn(inner_value__) {
        #("size", json.int(inner_value__))
      }),
    )),
  ))

  decode__read_response(result__)
  |> result.replace_error(chrome.ProtocolError)
}

/// Return UUID of Blob object specified by a remote object id.
/// 
/// Parameters:  
///  - `object_id` : Object id of a Blob object wrapper.
/// 
/// Returns:  
///  - `uuid` : UUID of the specified Blob.
/// 
pub fn resolve_blob(callback__, object_id object_id: runtime.RemoteObjectId) {
  use result__ <- result.try(callback__(
    "IO.resolveBlob",
    option.Some(
      json.object([#("objectId", runtime.encode__remote_object_id(object_id))]),
    ),
  ))

  decode__resolve_blob_response(result__)
  |> result.replace_error(chrome.ProtocolError)
}
