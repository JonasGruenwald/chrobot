//// > ⚙️  This module was generated from the Chrome DevTools Protocol version **1.3**
//// ## Fetch Domain  
////
//// A domain for letting clients substitute browser's network layer with client code.  
////
//// [📖   View this domain on the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/1-3/Fetch/)

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
import protocol/io
import protocol/network

/// Unique request identifier.
pub type RequestId {
  RequestId(String)
}

@internal
pub fn encode__request_id(value__: RequestId) {
  case value__ {
    RequestId(inner_value__) -> json.string(inner_value__)
  }
}

@internal
pub fn decode__request_id(value__: dynamic.Dynamic) {
  value__
  |> dynamic.decode1(RequestId, dynamic.string)
}

/// Stages of the request to handle. Request will intercept before the request is
/// sent. Response will intercept after the response is received (but before response
/// body is received).
pub type RequestStage {
  RequestStageRequest
  RequestStageResponse
}

@internal
pub fn encode__request_stage(value__: RequestStage) {
  case value__ {
    RequestStageRequest -> "Request"
    RequestStageResponse -> "Response"
  }
  |> json.string()
}

@internal
pub fn decode__request_stage(value__: dynamic.Dynamic) {
  case dynamic.string(value__) {
    Ok("Request") -> Ok(RequestStageRequest)
    Ok("Response") -> Ok(RequestStageResponse)
    Error(error) -> Error(error)
    Ok(other) ->
      Error([
        dynamic.DecodeError(
          expected: "valid enum property",
          found: other,
          path: ["enum decoder"],
        ),
      ])
  }
}

pub type RequestPattern {
  RequestPattern(
    url_pattern: option.Option(String),
    /// Wildcards (`'*'` -> zero or more, `'?'` -> exactly one) are allowed. Escape character is
    /// backslash. Omitting is equivalent to `"*"`.
    /// 
    resource_type: option.Option(network.ResourceType),
    /// If set, only requests for matching resource types will be intercepted.
    /// 
    request_stage: option.Option(RequestStage),
  )
}

/// Stage at which to begin intercepting requests. Default is Request.
/// 
@internal
pub fn encode__request_pattern(value__: RequestPattern) {
  json.object(
    []
    |> utils.add_optional(value__.url_pattern, fn(inner_value__) {
      #("urlPattern", json.string(inner_value__))
    })
    |> utils.add_optional(value__.resource_type, fn(inner_value__) {
      #("resourceType", network.encode__resource_type(inner_value__))
    })
    |> utils.add_optional(value__.request_stage, fn(inner_value__) {
      #("requestStage", encode__request_stage(inner_value__))
    }),
  )
}

@internal
pub fn decode__request_pattern(value__: dynamic.Dynamic) {
  use url_pattern <- result.try(dynamic.optional_field(
    "urlPattern",
    dynamic.string,
  )(value__))
  use resource_type <- result.try(dynamic.optional_field(
    "resourceType",
    network.decode__resource_type,
  )(value__))
  use request_stage <- result.try(dynamic.optional_field(
    "requestStage",
    decode__request_stage,
  )(value__))

  Ok(RequestPattern(
    url_pattern: url_pattern,
    resource_type: resource_type,
    request_stage: request_stage,
  ))
}

/// Response HTTP header entry
pub type HeaderEntry {
  HeaderEntry(name: String, value: String)
}

@internal
pub fn encode__header_entry(value__: HeaderEntry) {
  json.object([
    #("name", json.string(value__.name)),
    #("value", json.string(value__.value)),
  ])
}

@internal
pub fn decode__header_entry(value__: dynamic.Dynamic) {
  use name <- result.try(dynamic.field("name", dynamic.string)(value__))
  use value <- result.try(dynamic.field("value", dynamic.string)(value__))

  Ok(HeaderEntry(name: name, value: value))
}

/// Authorization challenge for HTTP status code 401 or 407.
pub type AuthChallenge {
  AuthChallenge(
    source: option.Option(AuthChallengeSource),
    /// Source of the authentication challenge.
    /// 
    origin: String,
    /// Origin of the challenger.
    /// 
    scheme: String,
    /// The authentication scheme used, such as basic or digest
    /// 
    realm: String,
  )
}

/// The realm of the challenge. May be empty.
/// 
/// This type is not part of the protocol spec, it has been generated dynamically 
/// to represent the possible values of the enum property `source` of `AuthChallenge`
pub type AuthChallengeSource {
  AuthChallengeSourceServer
  AuthChallengeSourceProxy
}

@internal
pub fn encode__auth_challenge_source(value__: AuthChallengeSource) {
  case value__ {
    AuthChallengeSourceServer -> "Server"
    AuthChallengeSourceProxy -> "Proxy"
  }
  |> json.string()
}

@internal
pub fn decode__auth_challenge_source(value__: dynamic.Dynamic) {
  case dynamic.string(value__) {
    Ok("Server") -> Ok(AuthChallengeSourceServer)
    Ok("Proxy") -> Ok(AuthChallengeSourceProxy)
    Error(error) -> Error(error)
    Ok(other) ->
      Error([
        dynamic.DecodeError(
          expected: "valid enum property",
          found: other,
          path: ["enum decoder"],
        ),
      ])
  }
}

@internal
pub fn encode__auth_challenge(value__: AuthChallenge) {
  json.object(
    [
      #("origin", json.string(value__.origin)),
      #("scheme", json.string(value__.scheme)),
      #("realm", json.string(value__.realm)),
    ]
    |> utils.add_optional(value__.source, fn(inner_value__) {
      #("source", encode__auth_challenge_source(inner_value__))
    }),
  )
}

@internal
pub fn decode__auth_challenge(value__: dynamic.Dynamic) {
  use source <- result.try(dynamic.optional_field(
    "source",
    decode__auth_challenge_source,
  )(value__))
  use origin <- result.try(dynamic.field("origin", dynamic.string)(value__))
  use scheme <- result.try(dynamic.field("scheme", dynamic.string)(value__))
  use realm <- result.try(dynamic.field("realm", dynamic.string)(value__))

  Ok(AuthChallenge(source: source, origin: origin, scheme: scheme, realm: realm))
}

/// Response to an AuthChallenge.
pub type AuthChallengeResponse {
  AuthChallengeResponse(
    response: AuthChallengeResponseResponse,
    /// The decision on what to do in response to the authorization challenge.  Default means
    /// deferring to the default behavior of the net stack, which will likely either the Cancel
    /// authentication or display a popup dialog box.
    /// 
    username: option.Option(String),
    /// The username to provide, possibly empty. Should only be set if response is
    /// ProvideCredentials.
    /// 
    password: option.Option(String),
  )
}

/// The password to provide, possibly empty. Should only be set if response is
/// ProvideCredentials.
/// 
/// This type is not part of the protocol spec, it has been generated dynamically 
/// to represent the possible values of the enum property `response` of `AuthChallengeResponse`
pub type AuthChallengeResponseResponse {
  AuthChallengeResponseResponseDefault
  AuthChallengeResponseResponseCancelAuth
  AuthChallengeResponseResponseProvideCredentials
}

@internal
pub fn encode__auth_challenge_response_response(value__: AuthChallengeResponseResponse) {
  case value__ {
    AuthChallengeResponseResponseDefault -> "Default"
    AuthChallengeResponseResponseCancelAuth -> "CancelAuth"
    AuthChallengeResponseResponseProvideCredentials -> "ProvideCredentials"
  }
  |> json.string()
}

@internal
pub fn decode__auth_challenge_response_response(value__: dynamic.Dynamic) {
  case dynamic.string(value__) {
    Ok("Default") -> Ok(AuthChallengeResponseResponseDefault)
    Ok("CancelAuth") -> Ok(AuthChallengeResponseResponseCancelAuth)
    Ok("ProvideCredentials") ->
      Ok(AuthChallengeResponseResponseProvideCredentials)
    Error(error) -> Error(error)
    Ok(other) ->
      Error([
        dynamic.DecodeError(
          expected: "valid enum property",
          found: other,
          path: ["enum decoder"],
        ),
      ])
  }
}

@internal
pub fn encode__auth_challenge_response(value__: AuthChallengeResponse) {
  json.object(
    [#("response", encode__auth_challenge_response_response(value__.response))]
    |> utils.add_optional(value__.username, fn(inner_value__) {
      #("username", json.string(inner_value__))
    })
    |> utils.add_optional(value__.password, fn(inner_value__) {
      #("password", json.string(inner_value__))
    }),
  )
}

@internal
pub fn decode__auth_challenge_response(value__: dynamic.Dynamic) {
  use response <- result.try(dynamic.field(
    "response",
    decode__auth_challenge_response_response,
  )(value__))
  use username <- result.try(dynamic.optional_field("username", dynamic.string)(
    value__,
  ))
  use password <- result.try(dynamic.optional_field("password", dynamic.string)(
    value__,
  ))

  Ok(AuthChallengeResponse(
    response: response,
    username: username,
    password: password,
  ))
}

/// This type is not part of the protocol spec, it has been generated dynamically
/// to represent the response to the command `get_response_body`
pub type GetResponseBodyResponse {
  GetResponseBodyResponse(
    body: String,
    /// Response body.
    /// 
    base64_encoded: Bool,
  )
}

/// True, if content was sent as base64.
/// 
@internal
pub fn decode__get_response_body_response(value__: dynamic.Dynamic) {
  use body <- result.try(dynamic.field("body", dynamic.string)(value__))
  use base64_encoded <- result.try(dynamic.field("base64Encoded", dynamic.bool)(
    value__,
  ))

  Ok(GetResponseBodyResponse(body: body, base64_encoded: base64_encoded))
}

/// This type is not part of the protocol spec, it has been generated dynamically
/// to represent the response to the command `take_response_body_as_stream`
pub type TakeResponseBodyAsStreamResponse {
  TakeResponseBodyAsStreamResponse(stream: io.StreamHandle)
}

@internal
pub fn decode__take_response_body_as_stream_response(value__: dynamic.Dynamic) {
  use stream <- result.try(dynamic.field("stream", io.decode__stream_handle)(
    value__,
  ))

  Ok(TakeResponseBodyAsStreamResponse(stream: stream))
}

/// Disables the fetch domain.
/// 
pub fn disable(callback__) {
  callback__("Fetch.disable", option.None)
}

/// Enables issuing of requestPaused events. A request will be paused until client
/// calls one of failRequest, fulfillRequest or continueRequest/continueWithAuth.
/// 
/// Parameters:  
///  - `patterns` : If specified, only requests matching any of these patterns will produce
/// fetchRequested event and will be paused until clients response. If not set,
/// all requests will be affected.
///  - `handle_auth_requests` : If true, authRequired events will be issued and requests will be paused
/// expecting a call to continueWithAuth.
/// 
/// Returns:  
/// 
pub fn enable(
  callback__,
  patterns patterns: option.Option(List(RequestPattern)),
  handle_auth_requests handle_auth_requests: option.Option(Bool),
) {
  callback__(
    "Fetch.enable",
    option.Some(json.object(
      []
      |> utils.add_optional(patterns, fn(inner_value__) {
        #("patterns", json.array(inner_value__, of: encode__request_pattern))
      })
      |> utils.add_optional(handle_auth_requests, fn(inner_value__) {
        #("handleAuthRequests", json.bool(inner_value__))
      }),
    )),
  )
}

/// Causes the request to fail with specified reason.
/// 
/// Parameters:  
///  - `request_id` : An id the client received in requestPaused event.
///  - `error_reason` : Causes the request to fail with the given reason.
/// 
/// Returns:  
/// 
pub fn fail_request(
  callback__,
  request_id request_id: RequestId,
  error_reason error_reason: network.ErrorReason,
) {
  callback__(
    "Fetch.failRequest",
    option.Some(
      json.object([
        #("requestId", encode__request_id(request_id)),
        #("errorReason", network.encode__error_reason(error_reason)),
      ]),
    ),
  )
}

/// Provides response to the request.
/// 
/// Parameters:  
///  - `request_id` : An id the client received in requestPaused event.
///  - `response_code` : An HTTP response code.
///  - `response_headers` : Response headers.
///  - `binary_response_headers` : Alternative way of specifying response headers as a \0-separated
/// series of name: value pairs. Prefer the above method unless you
/// need to represent some non-UTF8 values that can't be transmitted
/// over the protocol as text. (Encoded as a base64 string when passed over JSON)
///  - `body` : A response body. If absent, original response body will be used if
/// the request is intercepted at the response stage and empty body
/// will be used if the request is intercepted at the request stage. (Encoded as a base64 string when passed over JSON)
///  - `response_phrase` : A textual representation of responseCode.
/// If absent, a standard phrase matching responseCode is used.
/// 
/// Returns:  
/// 
pub fn fulfill_request(
  callback__,
  request_id request_id: RequestId,
  response_code response_code: Int,
  response_headers response_headers: option.Option(List(HeaderEntry)),
  binary_response_headers binary_response_headers: option.Option(String),
  body body: option.Option(String),
  response_phrase response_phrase: option.Option(String),
) {
  callback__(
    "Fetch.fulfillRequest",
    option.Some(json.object(
      [
        #("requestId", encode__request_id(request_id)),
        #("responseCode", json.int(response_code)),
      ]
      |> utils.add_optional(response_headers, fn(inner_value__) {
        #(
          "responseHeaders",
          json.array(inner_value__, of: encode__header_entry),
        )
      })
      |> utils.add_optional(binary_response_headers, fn(inner_value__) {
        #("binaryResponseHeaders", json.string(inner_value__))
      })
      |> utils.add_optional(body, fn(inner_value__) {
        #("body", json.string(inner_value__))
      })
      |> utils.add_optional(response_phrase, fn(inner_value__) {
        #("responsePhrase", json.string(inner_value__))
      }),
    )),
  )
}

/// Continues the request, optionally modifying some of its parameters.
/// 
/// Parameters:  
///  - `request_id` : An id the client received in requestPaused event.
///  - `url` : If set, the request url will be modified in a way that's not observable by page.
///  - `method` : If set, the request method is overridden.
///  - `post_data` : If set, overrides the post data in the request. (Encoded as a base64 string when passed over JSON)
///  - `headers` : If set, overrides the request headers. Note that the overrides do not
/// extend to subsequent redirect hops, if a redirect happens. Another override
/// may be applied to a different request produced by a redirect.
/// 
/// Returns:  
/// 
pub fn continue_request(
  callback__,
  request_id request_id: RequestId,
  url url: option.Option(String),
  method method: option.Option(String),
  post_data post_data: option.Option(String),
  headers headers: option.Option(List(HeaderEntry)),
) {
  callback__(
    "Fetch.continueRequest",
    option.Some(json.object(
      [#("requestId", encode__request_id(request_id))]
      |> utils.add_optional(url, fn(inner_value__) {
        #("url", json.string(inner_value__))
      })
      |> utils.add_optional(method, fn(inner_value__) {
        #("method", json.string(inner_value__))
      })
      |> utils.add_optional(post_data, fn(inner_value__) {
        #("postData", json.string(inner_value__))
      })
      |> utils.add_optional(headers, fn(inner_value__) {
        #("headers", json.array(inner_value__, of: encode__header_entry))
      }),
    )),
  )
}

/// Continues a request supplying authChallengeResponse following authRequired event.
/// 
/// Parameters:  
///  - `request_id` : An id the client received in authRequired event.
///  - `auth_challenge_response` : Response to  with an authChallenge.
/// 
/// Returns:  
/// 
pub fn continue_with_auth(
  callback__,
  request_id request_id: RequestId,
  auth_challenge_response auth_challenge_response: AuthChallengeResponse,
) {
  callback__(
    "Fetch.continueWithAuth",
    option.Some(
      json.object([
        #("requestId", encode__request_id(request_id)),
        #(
          "authChallengeResponse",
          encode__auth_challenge_response(auth_challenge_response),
        ),
      ]),
    ),
  )
}

/// Causes the body of the response to be received from the server and
/// returned as a single string. May only be issued for a request that
/// is paused in the Response stage and is mutually exclusive with
/// takeResponseBodyForInterceptionAsStream. Calling other methods that
/// affect the request or disabling fetch domain before body is received
/// results in an undefined behavior.
/// Note that the response body is not available for redirects. Requests
/// paused in the _redirect received_ state may be differentiated by
/// `responseCode` and presence of `location` response header, see
/// comments to `requestPaused` for details.
/// 
/// Parameters:  
///  - `request_id` : Identifier for the intercepted request to get body for.
/// 
/// Returns:  
///  - `body` : Response body.
///  - `base64_encoded` : True, if content was sent as base64.
/// 
pub fn get_response_body(callback__, request_id request_id: RequestId) {
  use result__ <- result.try(callback__(
    "Fetch.getResponseBody",
    option.Some(json.object([#("requestId", encode__request_id(request_id))])),
  ))

  decode__get_response_body_response(result__)
  |> result.replace_error(chrome.ProtocolError)
}

/// Returns a handle to the stream representing the response body.
/// The request must be paused in the HeadersReceived stage.
/// Note that after this command the request can't be continued
/// as is -- client either needs to cancel it or to provide the
/// response body.
/// The stream only supports sequential read, IO.read will fail if the position
/// is specified.
/// This method is mutually exclusive with getResponseBody.
/// Calling other methods that affect the request or disabling fetch
/// domain before body is received results in an undefined behavior.
/// 
/// Parameters:  
///  - `request_id`
/// 
/// Returns:  
///  - `stream`
/// 
pub fn take_response_body_as_stream(
  callback__,
  request_id request_id: RequestId,
) {
  use result__ <- result.try(callback__(
    "Fetch.takeResponseBodyAsStream",
    option.Some(json.object([#("requestId", encode__request_id(request_id))])),
  ))

  decode__take_response_body_as_stream_response(result__)
  |> result.replace_error(chrome.ProtocolError)
}
