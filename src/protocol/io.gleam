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

/// This is either obtained from another method or specified as `blob:<uuid>` where
/// `<uuid>` is an UUID of a Blob.
pub type StreamHandle {
  StreamHandle(String)
}
