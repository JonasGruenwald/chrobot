//// > ⚙️  This module was generated from the Chrome DevTools Protocol version **1.3**
//// ## Security Domain  
////
//// Security  
////
//// [📖   View this domain on the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/1-3/Security/)

// ---------------------------------------------------------------------------
// |  !!!!!!   This is an autogenerated file - Do not edit manually  !!!!!!  |
// | Run ` gleam run -m scripts/generate_protocol_bindings.sh` to regenerate.|  
// ---------------------------------------------------------------------------

import chrome
import gleam/dynamic
import gleam/json
import gleam/option
import gleam/result

/// An internal certificate ID value.
pub type CertificateId {
  CertificateId(Int)
}

@internal
pub fn encode__certificate_id(value__: CertificateId) {
  case value__ {
    CertificateId(inner_value__) -> json.int(inner_value__)
  }
}

@internal
pub fn decode__certificate_id(value__: dynamic.Dynamic) {
  dynamic.int(value__)
  |> result.replace_error(chrome.ProtocolError)
}

/// A description of mixed content (HTTP resources on HTTPS pages), as defined by
/// https://www.w3.org/TR/mixed-content/#categories
pub type MixedContentType {
  MixedContentTypeBlockable
  MixedContentTypeOptionallyBlockable
  MixedContentTypeNone
}

@internal
pub fn encode__mixed_content_type(value__: MixedContentType) {
  case value__ {
    MixedContentTypeBlockable -> "blockable"
    MixedContentTypeOptionallyBlockable -> "optionally-blockable"
    MixedContentTypeNone -> "none"
  }
  |> json.string()
}

@internal
pub fn decode__mixed_content_type(value__: dynamic.Dynamic) {
  case dynamic.string(value__) {
    Ok("blockable") -> Ok(MixedContentTypeBlockable)
    Ok("optionally-blockable") -> Ok(MixedContentTypeOptionallyBlockable)
    Ok("none") -> Ok(MixedContentTypeNone)
    _ -> Error(chrome.ProtocolError)
  }
}

/// The security level of a page or resource.
pub type SecurityState {
  SecurityStateUnknown
  SecurityStateNeutral
  SecurityStateInsecure
  SecurityStateSecure
  SecurityStateInfo
  SecurityStateInsecureBroken
}

@internal
pub fn encode__security_state(value__: SecurityState) {
  case value__ {
    SecurityStateUnknown -> "unknown"
    SecurityStateNeutral -> "neutral"
    SecurityStateInsecure -> "insecure"
    SecurityStateSecure -> "secure"
    SecurityStateInfo -> "info"
    SecurityStateInsecureBroken -> "insecure-broken"
  }
  |> json.string()
}

@internal
pub fn decode__security_state(value__: dynamic.Dynamic) {
  case dynamic.string(value__) {
    Ok("unknown") -> Ok(SecurityStateUnknown)
    Ok("neutral") -> Ok(SecurityStateNeutral)
    Ok("insecure") -> Ok(SecurityStateInsecure)
    Ok("secure") -> Ok(SecurityStateSecure)
    Ok("info") -> Ok(SecurityStateInfo)
    Ok("insecure-broken") -> Ok(SecurityStateInsecureBroken)
    _ -> Error(chrome.ProtocolError)
  }
}

/// An explanation of an factor contributing to the security state.
pub type SecurityStateExplanation {
  SecurityStateExplanation(
    security_state: SecurityState,
    title: String,
    summary: String,
    description: String,
    mixed_content_type: MixedContentType,
    certificate: List(String),
    recommendations: option.Option(List(String)),
  )
}

@internal
pub fn encode__security_state_explanation(value__: SecurityStateExplanation) {
  json.object([
    #("securityState", encode__security_state(value__.security_state)),
    #("title", json.string(value__.title)),
    #("summary", json.string(value__.summary)),
    #("description", json.string(value__.description)),
    #(
      "mixedContentType",
      encode__mixed_content_type(value__.mixed_content_type),
    ),
    #("certificate", json.array(value__.certificate, of: json.string)),
    #("recommendations", {
      case value__.recommendations {
        option.Some(value__) -> json.array(value__, of: json.string)
        option.None -> json.null()
      }
    }),
  ])
}

// TODO implement decoder for Object with props
/// The action to take when a certificate error occurs. continue will continue processing the
/// request and cancel will cancel the request.
pub type CertificateErrorAction {
  CertificateErrorActionContinue
  CertificateErrorActionCancel
}

@internal
pub fn encode__certificate_error_action(value__: CertificateErrorAction) {
  case value__ {
    CertificateErrorActionContinue -> "continue"
    CertificateErrorActionCancel -> "cancel"
  }
  |> json.string()
}

@internal
pub fn decode__certificate_error_action(value__: dynamic.Dynamic) {
  case dynamic.string(value__) {
    Ok("continue") -> Ok(CertificateErrorActionContinue)
    Ok("cancel") -> Ok(CertificateErrorActionCancel)
    _ -> Error(chrome.ProtocolError)
  }
}
