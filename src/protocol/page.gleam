//// > ⚙️  This module was generated from the Chrome DevTools Protocol version **1.3**
//// ## Page Domain  
////
//// Actions and events related to the inspected page belong to the page domain.  
////
//// [📖   View this domain on the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/1-3/Page/)

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
import protocol/dom
import protocol/network
import protocol/runtime

/// Unique frame identifier.
pub type FrameId {
  FrameId(String)
}

@internal
pub fn encode__frame_id(value__: FrameId) {
  case value__ {
    FrameId(inner_value__) -> json.string(inner_value__)
  }
}

@internal
pub fn decode__frame_id(value__: dynamic.Dynamic) {
  value__
  |> dynamic.decode1(FrameId, dynamic.string)
}

/// Information about the Frame on the page.
pub type Frame {
  Frame(
    id: FrameId,
    /// Frame unique identifier.
    /// 
    parent_id: option.Option(FrameId),
    /// Parent frame identifier.
    /// 
    loader_id: network.LoaderId,
    /// Identifier of the loader associated with this frame.
    /// 
    name: option.Option(String),
    /// Frame's name as specified in the tag.
    /// 
    url: String,
    /// Frame document's URL without fragment.
    /// 
    security_origin: String,
    /// Frame document's security origin.
    /// 
    mime_type: String,
  )
}

/// Frame document's mimeType as determined by the browser.
/// 
@internal
pub fn encode__frame(value__: Frame) {
  json.object(
    [
      #("id", encode__frame_id(value__.id)),
      #("loaderId", network.encode__loader_id(value__.loader_id)),
      #("url", json.string(value__.url)),
      #("securityOrigin", json.string(value__.security_origin)),
      #("mimeType", json.string(value__.mime_type)),
    ]
    |> utils.add_optional(value__.parent_id, fn(inner_value__) {
      #("parentId", encode__frame_id(inner_value__))
    })
    |> utils.add_optional(value__.name, fn(inner_value__) {
      #("name", json.string(inner_value__))
    }),
  )
}

@internal
pub fn decode__frame(value__: dynamic.Dynamic) {
  use id <- result.try(dynamic.field("id", decode__frame_id)(value__))
  use parent_id <- result.try(dynamic.optional_field(
    "parentId",
    decode__frame_id,
  )(value__))
  use loader_id <- result.try(dynamic.field(
    "loaderId",
    network.decode__loader_id,
  )(value__))
  use name <- result.try(dynamic.optional_field("name", dynamic.string)(value__))
  use url <- result.try(dynamic.field("url", dynamic.string)(value__))
  use security_origin <- result.try(dynamic.field(
    "securityOrigin",
    dynamic.string,
  )(value__))
  use mime_type <- result.try(dynamic.field("mimeType", dynamic.string)(value__))

  Ok(Frame(
    id: id,
    parent_id: parent_id,
    loader_id: loader_id,
    name: name,
    url: url,
    security_origin: security_origin,
    mime_type: mime_type,
  ))
}

/// Information about the Frame hierarchy.
pub type FrameTree {
  FrameTree(
    frame: Frame,
    /// Frame information for this tree item.
    /// 
    child_frames: option.Option(List(FrameTree)),
  )
}

/// Child frames.
/// 
@internal
pub fn encode__frame_tree(value__: FrameTree) {
  json.object(
    [#("frame", encode__frame(value__.frame))]
    |> utils.add_optional(value__.child_frames, fn(inner_value__) {
      #("childFrames", json.array(inner_value__, of: encode__frame_tree))
    }),
  )
}

@internal
pub fn decode__frame_tree(value__: dynamic.Dynamic) {
  use frame <- result.try(dynamic.field("frame", decode__frame)(value__))
  use child_frames <- result.try(dynamic.optional_field(
    "childFrames",
    dynamic.list(decode__frame_tree),
  )(value__))

  Ok(FrameTree(frame: frame, child_frames: child_frames))
}

/// Unique script identifier.
pub type ScriptIdentifier {
  ScriptIdentifier(String)
}

@internal
pub fn encode__script_identifier(value__: ScriptIdentifier) {
  case value__ {
    ScriptIdentifier(inner_value__) -> json.string(inner_value__)
  }
}

@internal
pub fn decode__script_identifier(value__: dynamic.Dynamic) {
  value__
  |> dynamic.decode1(ScriptIdentifier, dynamic.string)
}

/// Transition type.
pub type TransitionType {
  TransitionTypeLink
  TransitionTypeTyped
  TransitionTypeAddressBar
  TransitionTypeAutoBookmark
  TransitionTypeAutoSubframe
  TransitionTypeManualSubframe
  TransitionTypeGenerated
  TransitionTypeAutoToplevel
  TransitionTypeFormSubmit
  TransitionTypeReload
  TransitionTypeKeyword
  TransitionTypeKeywordGenerated
  TransitionTypeOther
}

@internal
pub fn encode__transition_type(value__: TransitionType) {
  case value__ {
    TransitionTypeLink -> "link"
    TransitionTypeTyped -> "typed"
    TransitionTypeAddressBar -> "address_bar"
    TransitionTypeAutoBookmark -> "auto_bookmark"
    TransitionTypeAutoSubframe -> "auto_subframe"
    TransitionTypeManualSubframe -> "manual_subframe"
    TransitionTypeGenerated -> "generated"
    TransitionTypeAutoToplevel -> "auto_toplevel"
    TransitionTypeFormSubmit -> "form_submit"
    TransitionTypeReload -> "reload"
    TransitionTypeKeyword -> "keyword"
    TransitionTypeKeywordGenerated -> "keyword_generated"
    TransitionTypeOther -> "other"
  }
  |> json.string()
}

@internal
pub fn decode__transition_type(value__: dynamic.Dynamic) {
  case dynamic.string(value__) {
    Ok("link") -> Ok(TransitionTypeLink)
    Ok("typed") -> Ok(TransitionTypeTyped)
    Ok("address_bar") -> Ok(TransitionTypeAddressBar)
    Ok("auto_bookmark") -> Ok(TransitionTypeAutoBookmark)
    Ok("auto_subframe") -> Ok(TransitionTypeAutoSubframe)
    Ok("manual_subframe") -> Ok(TransitionTypeManualSubframe)
    Ok("generated") -> Ok(TransitionTypeGenerated)
    Ok("auto_toplevel") -> Ok(TransitionTypeAutoToplevel)
    Ok("form_submit") -> Ok(TransitionTypeFormSubmit)
    Ok("reload") -> Ok(TransitionTypeReload)
    Ok("keyword") -> Ok(TransitionTypeKeyword)
    Ok("keyword_generated") -> Ok(TransitionTypeKeywordGenerated)
    Ok("other") -> Ok(TransitionTypeOther)
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

/// Navigation history entry.
pub type NavigationEntry {
  NavigationEntry(
    id: Int,
    /// Unique id of the navigation history entry.
    /// 
    url: String,
    /// URL of the navigation history entry.
    /// 
    user_typed_url: String,
    /// URL that the user typed in the url bar.
    /// 
    title: String,
    /// Title of the navigation history entry.
    /// 
    transition_type: TransitionType,
  )
}

/// Transition type.
/// 
@internal
pub fn encode__navigation_entry(value__: NavigationEntry) {
  json.object([
    #("id", json.int(value__.id)),
    #("url", json.string(value__.url)),
    #("userTypedURL", json.string(value__.user_typed_url)),
    #("title", json.string(value__.title)),
    #("transitionType", encode__transition_type(value__.transition_type)),
  ])
}

@internal
pub fn decode__navigation_entry(value__: dynamic.Dynamic) {
  use id <- result.try(dynamic.field("id", dynamic.int)(value__))
  use url <- result.try(dynamic.field("url", dynamic.string)(value__))
  use user_typed_url <- result.try(dynamic.field("userTypedURL", dynamic.string)(
    value__,
  ))
  use title <- result.try(dynamic.field("title", dynamic.string)(value__))
  use transition_type <- result.try(dynamic.field(
    "transitionType",
    decode__transition_type,
  )(value__))

  Ok(NavigationEntry(
    id: id,
    url: url,
    user_typed_url: user_typed_url,
    title: title,
    transition_type: transition_type,
  ))
}

/// Javascript dialog type.
pub type DialogType {
  DialogTypeAlert
  DialogTypeConfirm
  DialogTypePrompt
  DialogTypeBeforeunload
}

@internal
pub fn encode__dialog_type(value__: DialogType) {
  case value__ {
    DialogTypeAlert -> "alert"
    DialogTypeConfirm -> "confirm"
    DialogTypePrompt -> "prompt"
    DialogTypeBeforeunload -> "beforeunload"
  }
  |> json.string()
}

@internal
pub fn decode__dialog_type(value__: dynamic.Dynamic) {
  case dynamic.string(value__) {
    Ok("alert") -> Ok(DialogTypeAlert)
    Ok("confirm") -> Ok(DialogTypeConfirm)
    Ok("prompt") -> Ok(DialogTypePrompt)
    Ok("beforeunload") -> Ok(DialogTypeBeforeunload)
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

/// Error while paring app manifest.
pub type AppManifestError {
  AppManifestError(
    message: String,
    /// Error message.
    /// 
    critical: Int,
    /// If critical, this is a non-recoverable parse error.
    /// 
    line: Int,
    /// Error line.
    /// 
    column: Int,
  )
}

/// Error column.
/// 
@internal
pub fn encode__app_manifest_error(value__: AppManifestError) {
  json.object([
    #("message", json.string(value__.message)),
    #("critical", json.int(value__.critical)),
    #("line", json.int(value__.line)),
    #("column", json.int(value__.column)),
  ])
}

@internal
pub fn decode__app_manifest_error(value__: dynamic.Dynamic) {
  use message <- result.try(dynamic.field("message", dynamic.string)(value__))
  use critical <- result.try(dynamic.field("critical", dynamic.int)(value__))
  use line <- result.try(dynamic.field("line", dynamic.int)(value__))
  use column <- result.try(dynamic.field("column", dynamic.int)(value__))

  Ok(AppManifestError(
    message: message,
    critical: critical,
    line: line,
    column: column,
  ))
}

/// Layout viewport position and dimensions.
pub type LayoutViewport {
  LayoutViewport(
    page_x: Int,
    /// Horizontal offset relative to the document (CSS pixels).
    /// 
    page_y: Int,
    /// Vertical offset relative to the document (CSS pixels).
    /// 
    client_width: Int,
    /// Width (CSS pixels), excludes scrollbar if present.
    /// 
    client_height: Int,
  )
}

/// Height (CSS pixels), excludes scrollbar if present.
/// 
@internal
pub fn encode__layout_viewport(value__: LayoutViewport) {
  json.object([
    #("pageX", json.int(value__.page_x)),
    #("pageY", json.int(value__.page_y)),
    #("clientWidth", json.int(value__.client_width)),
    #("clientHeight", json.int(value__.client_height)),
  ])
}

@internal
pub fn decode__layout_viewport(value__: dynamic.Dynamic) {
  use page_x <- result.try(dynamic.field("pageX", dynamic.int)(value__))
  use page_y <- result.try(dynamic.field("pageY", dynamic.int)(value__))
  use client_width <- result.try(dynamic.field("clientWidth", dynamic.int)(
    value__,
  ))
  use client_height <- result.try(dynamic.field("clientHeight", dynamic.int)(
    value__,
  ))

  Ok(LayoutViewport(
    page_x: page_x,
    page_y: page_y,
    client_width: client_width,
    client_height: client_height,
  ))
}

/// Visual viewport position, dimensions, and scale.
pub type VisualViewport {
  VisualViewport(
    offset_x: Float,
    /// Horizontal offset relative to the layout viewport (CSS pixels).
    /// 
    offset_y: Float,
    /// Vertical offset relative to the layout viewport (CSS pixels).
    /// 
    page_x: Float,
    /// Horizontal offset relative to the document (CSS pixels).
    /// 
    page_y: Float,
    /// Vertical offset relative to the document (CSS pixels).
    /// 
    client_width: Float,
    /// Width (CSS pixels), excludes scrollbar if present.
    /// 
    client_height: Float,
    /// Height (CSS pixels), excludes scrollbar if present.
    /// 
    scale: Float,
    /// Scale relative to the ideal viewport (size at width=device-width).
    /// 
    zoom: option.Option(Float),
  )
}

/// Page zoom factor (CSS to device independent pixels ratio).
/// 
@internal
pub fn encode__visual_viewport(value__: VisualViewport) {
  json.object(
    [
      #("offsetX", json.float(value__.offset_x)),
      #("offsetY", json.float(value__.offset_y)),
      #("pageX", json.float(value__.page_x)),
      #("pageY", json.float(value__.page_y)),
      #("clientWidth", json.float(value__.client_width)),
      #("clientHeight", json.float(value__.client_height)),
      #("scale", json.float(value__.scale)),
    ]
    |> utils.add_optional(value__.zoom, fn(inner_value__) {
      #("zoom", json.float(inner_value__))
    }),
  )
}

@internal
pub fn decode__visual_viewport(value__: dynamic.Dynamic) {
  use offset_x <- result.try(dynamic.field("offsetX", dynamic.float)(value__))
  use offset_y <- result.try(dynamic.field("offsetY", dynamic.float)(value__))
  use page_x <- result.try(dynamic.field("pageX", dynamic.float)(value__))
  use page_y <- result.try(dynamic.field("pageY", dynamic.float)(value__))
  use client_width <- result.try(dynamic.field("clientWidth", dynamic.float)(
    value__,
  ))
  use client_height <- result.try(dynamic.field("clientHeight", dynamic.float)(
    value__,
  ))
  use scale <- result.try(dynamic.field("scale", dynamic.float)(value__))
  use zoom <- result.try(dynamic.optional_field("zoom", dynamic.float)(value__))

  Ok(VisualViewport(
    offset_x: offset_x,
    offset_y: offset_y,
    page_x: page_x,
    page_y: page_y,
    client_width: client_width,
    client_height: client_height,
    scale: scale,
    zoom: zoom,
  ))
}

/// Viewport for capturing screenshot.
pub type Viewport {
  Viewport(
    x: Float,
    /// X offset in device independent pixels (dip).
    /// 
    y: Float,
    /// Y offset in device independent pixels (dip).
    /// 
    width: Float,
    /// Rectangle width in device independent pixels (dip).
    /// 
    height: Float,
    /// Rectangle height in device independent pixels (dip).
    /// 
    scale: Float,
  )
}

/// Page scale factor.
/// 
@internal
pub fn encode__viewport(value__: Viewport) {
  json.object([
    #("x", json.float(value__.x)),
    #("y", json.float(value__.y)),
    #("width", json.float(value__.width)),
    #("height", json.float(value__.height)),
    #("scale", json.float(value__.scale)),
  ])
}

@internal
pub fn decode__viewport(value__: dynamic.Dynamic) {
  use x <- result.try(dynamic.field("x", dynamic.float)(value__))
  use y <- result.try(dynamic.field("y", dynamic.float)(value__))
  use width <- result.try(dynamic.field("width", dynamic.float)(value__))
  use height <- result.try(dynamic.field("height", dynamic.float)(value__))
  use scale <- result.try(dynamic.field("scale", dynamic.float)(value__))

  Ok(Viewport(x: x, y: y, width: width, height: height, scale: scale))
}

/// This type is not part of the protocol spec, it has been generated dynamically
/// to represent the response to the command `add_script_to_evaluate_on_new_document`
pub type AddScriptToEvaluateOnNewDocumentResponse {
  AddScriptToEvaluateOnNewDocumentResponse(identifier: ScriptIdentifier)
}

/// Identifier of the added script.
/// 
@internal
pub fn decode__add_script_to_evaluate_on_new_document_response(value__: dynamic.Dynamic) {
  use identifier <- result.try(dynamic.field(
    "identifier",
    decode__script_identifier,
  )(value__))

  Ok(AddScriptToEvaluateOnNewDocumentResponse(identifier: identifier))
}

/// This type is not part of the protocol spec, it has been generated dynamically
/// to represent the response to the command `capture_screenshot`
pub type CaptureScreenshotResponse {
  CaptureScreenshotResponse(data: String)
}

/// Base64-encoded image data. (Encoded as a base64 string when passed over JSON)
/// 
@internal
pub fn decode__capture_screenshot_response(value__: dynamic.Dynamic) {
  use data <- result.try(dynamic.field("data", dynamic.string)(value__))

  Ok(CaptureScreenshotResponse(data: data))
}

/// This type is not part of the protocol spec, it has been generated dynamically
/// to represent the response to the command `create_isolated_world`
pub type CreateIsolatedWorldResponse {
  CreateIsolatedWorldResponse(execution_context_id: runtime.ExecutionContextId)
}

/// Execution context of the isolated world.
/// 
@internal
pub fn decode__create_isolated_world_response(value__: dynamic.Dynamic) {
  use execution_context_id <- result.try(dynamic.field(
    "executionContextId",
    runtime.decode__execution_context_id,
  )(value__))

  Ok(CreateIsolatedWorldResponse(execution_context_id: execution_context_id))
}

/// This type is not part of the protocol spec, it has been generated dynamically
/// to represent the response to the command `get_app_manifest`
pub type GetAppManifestResponse {
  GetAppManifestResponse(
    url: String,
    /// Manifest location.
    /// 
    errors: List(AppManifestError),
    data: option.Option(String),
  )
}

/// Manifest content.
/// 
@internal
pub fn decode__get_app_manifest_response(value__: dynamic.Dynamic) {
  use url <- result.try(dynamic.field("url", dynamic.string)(value__))
  use errors <- result.try(dynamic.field(
    "errors",
    dynamic.list(decode__app_manifest_error),
  )(value__))
  use data <- result.try(dynamic.optional_field("data", dynamic.string)(value__))

  Ok(GetAppManifestResponse(url: url, errors: errors, data: data))
}

/// This type is not part of the protocol spec, it has been generated dynamically
/// to represent the response to the command `get_frame_tree`
pub type GetFrameTreeResponse {
  GetFrameTreeResponse(frame_tree: FrameTree)
}

/// Present frame tree structure.
/// 
@internal
pub fn decode__get_frame_tree_response(value__: dynamic.Dynamic) {
  use frame_tree <- result.try(dynamic.field("frameTree", decode__frame_tree)(
    value__,
  ))

  Ok(GetFrameTreeResponse(frame_tree: frame_tree))
}

/// This type is not part of the protocol spec, it has been generated dynamically
/// to represent the response to the command `get_layout_metrics`
pub type GetLayoutMetricsResponse {
  GetLayoutMetricsResponse(
    css_layout_viewport: LayoutViewport,
    /// Metrics relating to the layout viewport in CSS pixels.
    /// 
    css_visual_viewport: VisualViewport,
    /// Metrics relating to the visual viewport in CSS pixels.
    /// 
    css_content_size: dom.Rect,
  )
}

/// Size of scrollable area in CSS pixels.
/// 
@internal
pub fn decode__get_layout_metrics_response(value__: dynamic.Dynamic) {
  use css_layout_viewport <- result.try(dynamic.field(
    "cssLayoutViewport",
    decode__layout_viewport,
  )(value__))
  use css_visual_viewport <- result.try(dynamic.field(
    "cssVisualViewport",
    decode__visual_viewport,
  )(value__))
  use css_content_size <- result.try(dynamic.field(
    "cssContentSize",
    dom.decode__rect,
  )(value__))

  Ok(GetLayoutMetricsResponse(
    css_layout_viewport: css_layout_viewport,
    css_visual_viewport: css_visual_viewport,
    css_content_size: css_content_size,
  ))
}

/// This type is not part of the protocol spec, it has been generated dynamically
/// to represent the response to the command `get_navigation_history`
pub type GetNavigationHistoryResponse {
  GetNavigationHistoryResponse(
    current_index: Int,
    /// Index of the current navigation history entry.
    /// 
    entries: List(NavigationEntry),
  )
}

/// Array of navigation history entries.
/// 
@internal
pub fn decode__get_navigation_history_response(value__: dynamic.Dynamic) {
  use current_index <- result.try(dynamic.field("currentIndex", dynamic.int)(
    value__,
  ))
  use entries <- result.try(dynamic.field(
    "entries",
    dynamic.list(decode__navigation_entry),
  )(value__))

  Ok(GetNavigationHistoryResponse(
    current_index: current_index,
    entries: entries,
  ))
}

/// This type is not part of the protocol spec, it has been generated dynamically
/// to represent the response to the command `navigate`
pub type NavigateResponse {
  NavigateResponse(
    frame_id: FrameId,
    /// Frame id that has navigated (or failed to navigate)
    /// 
    loader_id: option.Option(network.LoaderId),
    /// Loader identifier. This is omitted in case of same-document navigation,
    /// as the previously committed loaderId would not change.
    /// 
    error_text: option.Option(String),
  )
}

/// User friendly error message, present if and only if navigation has failed.
/// 
@internal
pub fn decode__navigate_response(value__: dynamic.Dynamic) {
  use frame_id <- result.try(dynamic.field("frameId", decode__frame_id)(value__))
  use loader_id <- result.try(dynamic.optional_field(
    "loaderId",
    network.decode__loader_id,
  )(value__))
  use error_text <- result.try(dynamic.optional_field(
    "errorText",
    dynamic.string,
  )(value__))

  Ok(NavigateResponse(
    frame_id: frame_id,
    loader_id: loader_id,
    error_text: error_text,
  ))
}

/// This type is not part of the protocol spec, it has been generated dynamically
/// to represent the response to the command `print_to_pdf`
pub type PrintToPdfResponse {
  PrintToPdfResponse(data: String)
}

/// Base64-encoded pdf data. Empty if |returnAsStream| is specified. (Encoded as a base64 string when passed over JSON)
/// 
@internal
pub fn decode__print_to_pdf_response(value__: dynamic.Dynamic) {
  use data <- result.try(dynamic.field("data", dynamic.string)(value__))

  Ok(PrintToPdfResponse(data: data))
}

/// Evaluates given script in every frame upon creation (before loading frame's scripts).
/// 
/// Parameters:  
///  - `source`
/// 
/// Returns:  
///  - `identifier` : Identifier of the added script.
/// 
pub fn add_script_to_evaluate_on_new_document(callback__, source source: String) {
  use result__ <- result.try(callback__(
    "Page.addScriptToEvaluateOnNewDocument",
    option.Some(json.object([#("source", json.string(source))])),
  ))

  decode__add_script_to_evaluate_on_new_document_response(result__)
  |> result.replace_error(chrome.ProtocolError)
}

/// Brings page to front (activates tab).
/// 
pub fn bring_to_front(callback__) {
  callback__("Page.bringToFront", option.None)
}

/// Capture page screenshot.
/// 
/// Parameters:  
///  - `format` : Image compression format (defaults to png).
///  - `quality` : Compression quality from range [0..100] (jpeg only).
///  - `clip` : Capture the screenshot of a given region only.
/// 
/// Returns:  
///  - `data` : Base64-encoded image data. (Encoded as a base64 string when passed over JSON)
/// 
pub fn capture_screenshot(
  callback__,
  format format: option.Option(CaptureScreenshotFormat),
  quality quality: option.Option(Int),
  clip clip: option.Option(Viewport),
) {
  use result__ <- result.try(callback__(
    "Page.captureScreenshot",
    option.Some(json.object(
      []
      |> utils.add_optional(format, fn(inner_value__) {
        #("format", encode__capture_screenshot_format(inner_value__))
      })
      |> utils.add_optional(quality, fn(inner_value__) {
        #("quality", json.int(inner_value__))
      })
      |> utils.add_optional(clip, fn(inner_value__) {
        #("clip", encode__viewport(inner_value__))
      }),
    )),
  ))

  decode__capture_screenshot_response(result__)
  |> result.replace_error(chrome.ProtocolError)
}

/// This type is not part of the protocol spec, it has been generated dynamically 
/// to represent the possible values of the enum property `format` of `captureScreenshot`
pub type CaptureScreenshotFormat {
  CaptureScreenshotFormatJpeg
  CaptureScreenshotFormatPng
  CaptureScreenshotFormatWebp
}

@internal
pub fn encode__capture_screenshot_format(value__: CaptureScreenshotFormat) {
  case value__ {
    CaptureScreenshotFormatJpeg -> "jpeg"
    CaptureScreenshotFormatPng -> "png"
    CaptureScreenshotFormatWebp -> "webp"
  }
  |> json.string()
}

@internal
pub fn decode__capture_screenshot_format(value__: dynamic.Dynamic) {
  case dynamic.string(value__) {
    Ok("jpeg") -> Ok(CaptureScreenshotFormatJpeg)
    Ok("png") -> Ok(CaptureScreenshotFormatPng)
    Ok("webp") -> Ok(CaptureScreenshotFormatWebp)
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

/// Creates an isolated world for the given frame.
/// 
/// Parameters:  
///  - `frame_id` : Id of the frame in which the isolated world should be created.
///  - `world_name` : An optional name which is reported in the Execution Context.
///  - `grant_univeral_access` : Whether or not universal access should be granted to the isolated world. This is a powerful
/// option, use with caution.
/// 
/// Returns:  
///  - `execution_context_id` : Execution context of the isolated world.
/// 
pub fn create_isolated_world(
  callback__,
  frame_id frame_id: FrameId,
  world_name world_name: option.Option(String),
  grant_univeral_access grant_univeral_access: option.Option(Bool),
) {
  use result__ <- result.try(callback__(
    "Page.createIsolatedWorld",
    option.Some(json.object(
      [#("frameId", encode__frame_id(frame_id))]
      |> utils.add_optional(world_name, fn(inner_value__) {
        #("worldName", json.string(inner_value__))
      })
      |> utils.add_optional(grant_univeral_access, fn(inner_value__) {
        #("grantUniveralAccess", json.bool(inner_value__))
      }),
    )),
  ))

  decode__create_isolated_world_response(result__)
  |> result.replace_error(chrome.ProtocolError)
}

/// Disables page domain notifications.
/// 
pub fn disable(callback__) {
  callback__("Page.disable", option.None)
}

/// Enables page domain notifications.
/// 
pub fn enable(callback__) {
  callback__("Page.enable", option.None)
}

/// Gets the processed manifest for this current document.
///   This API always waits for the manifest to be loaded.
///   If manifestId is provided, and it does not match the manifest of the
///     current document, this API errors out.
///   If there is not a loaded page, this API errors out immediately.
/// 
/// Parameters:  
///  - `manifest_id`
/// 
/// Returns:  
///  - `url` : Manifest location.
///  - `errors`
///  - `data` : Manifest content.
/// 
pub fn get_app_manifest(
  callback__,
  manifest_id manifest_id: option.Option(String),
) {
  use result__ <- result.try(callback__(
    "Page.getAppManifest",
    option.Some(json.object(
      []
      |> utils.add_optional(manifest_id, fn(inner_value__) {
        #("manifestId", json.string(inner_value__))
      }),
    )),
  ))

  decode__get_app_manifest_response(result__)
  |> result.replace_error(chrome.ProtocolError)
}

/// Returns present frame tree structure.
///  - `frame_tree` : Present frame tree structure.
/// 
pub fn get_frame_tree(callback__) {
  use result__ <- result.try(callback__("Page.getFrameTree", option.None))

  decode__get_frame_tree_response(result__)
  |> result.replace_error(chrome.ProtocolError)
}

/// Returns metrics relating to the layouting of the page, such as viewport bounds/scale.
///  - `css_layout_viewport` : Metrics relating to the layout viewport in CSS pixels.
///  - `css_visual_viewport` : Metrics relating to the visual viewport in CSS pixels.
///  - `css_content_size` : Size of scrollable area in CSS pixels.
/// 
pub fn get_layout_metrics(callback__) {
  use result__ <- result.try(callback__("Page.getLayoutMetrics", option.None))

  decode__get_layout_metrics_response(result__)
  |> result.replace_error(chrome.ProtocolError)
}

/// Returns navigation history for the current page.
///  - `current_index` : Index of the current navigation history entry.
///  - `entries` : Array of navigation history entries.
/// 
pub fn get_navigation_history(callback__) {
  use result__ <- result.try(callback__(
    "Page.getNavigationHistory",
    option.None,
  ))

  decode__get_navigation_history_response(result__)
  |> result.replace_error(chrome.ProtocolError)
}

/// Resets navigation history for the current page.
/// 
pub fn reset_navigation_history(callback__) {
  callback__("Page.resetNavigationHistory", option.None)
}

/// Accepts or dismisses a JavaScript initiated dialog (alert, confirm, prompt, or onbeforeunload).
/// 
/// Parameters:  
///  - `accept` : Whether to accept or dismiss the dialog.
///  - `prompt_text` : The text to enter into the dialog prompt before accepting. Used only if this is a prompt
/// dialog.
/// 
/// Returns:  
/// 
pub fn handle_java_script_dialog(
  callback__,
  accept accept: Bool,
  prompt_text prompt_text: option.Option(String),
) {
  callback__(
    "Page.handleJavaScriptDialog",
    option.Some(json.object(
      [#("accept", json.bool(accept))]
      |> utils.add_optional(prompt_text, fn(inner_value__) {
        #("promptText", json.string(inner_value__))
      }),
    )),
  )
}

/// Navigates current page to the given URL.
/// 
/// Parameters:  
///  - `url` : URL to navigate the page to.
///  - `referrer` : Referrer URL.
///  - `transition_type` : Intended transition type.
///  - `frame_id` : Frame id to navigate, if not specified navigates the top frame.
/// 
/// Returns:  
///  - `frame_id` : Frame id that has navigated (or failed to navigate)
///  - `loader_id` : Loader identifier. This is omitted in case of same-document navigation,
/// as the previously committed loaderId would not change.
///  - `error_text` : User friendly error message, present if and only if navigation has failed.
/// 
pub fn navigate(
  callback__,
  url url: String,
  referrer referrer: option.Option(String),
  transition_type transition_type: option.Option(TransitionType),
  frame_id frame_id: option.Option(FrameId),
) {
  use result__ <- result.try(callback__(
    "Page.navigate",
    option.Some(json.object(
      [#("url", json.string(url))]
      |> utils.add_optional(referrer, fn(inner_value__) {
        #("referrer", json.string(inner_value__))
      })
      |> utils.add_optional(transition_type, fn(inner_value__) {
        #("transitionType", encode__transition_type(inner_value__))
      })
      |> utils.add_optional(frame_id, fn(inner_value__) {
        #("frameId", encode__frame_id(inner_value__))
      }),
    )),
  ))

  decode__navigate_response(result__)
  |> result.replace_error(chrome.ProtocolError)
}

/// Navigates current page to the given history entry.
/// 
/// Parameters:  
///  - `entry_id` : Unique id of the entry to navigate to.
/// 
/// Returns:  
/// 
pub fn navigate_to_history_entry(callback__, entry_id entry_id: Int) {
  callback__(
    "Page.navigateToHistoryEntry",
    option.Some(json.object([#("entryId", json.int(entry_id))])),
  )
}

/// Print page as PDF.
/// 
/// Parameters:  
///  - `landscape` : Paper orientation. Defaults to false.
///  - `display_header_footer` : Display header and footer. Defaults to false.
///  - `print_background` : Print background graphics. Defaults to false.
///  - `scale` : Scale of the webpage rendering. Defaults to 1.
///  - `paper_width` : Paper width in inches. Defaults to 8.5 inches.
///  - `paper_height` : Paper height in inches. Defaults to 11 inches.
///  - `margin_top` : Top margin in inches. Defaults to 1cm (~0.4 inches).
///  - `margin_bottom` : Bottom margin in inches. Defaults to 1cm (~0.4 inches).
///  - `margin_left` : Left margin in inches. Defaults to 1cm (~0.4 inches).
///  - `margin_right` : Right margin in inches. Defaults to 1cm (~0.4 inches).
///  - `page_ranges` : Paper ranges to print, one based, e.g., '1-5, 8, 11-13'. Pages are
/// printed in the document order, not in the order specified, and no
/// more than once.
/// Defaults to empty string, which implies the entire document is printed.
/// The page numbers are quietly capped to actual page count of the
/// document, and ranges beyond the end of the document are ignored.
/// If this results in no pages to print, an error is reported.
/// It is an error to specify a range with start greater than end.
///  - `header_template` : HTML template for the print header. Should be valid HTML markup with following
/// classes used to inject printing values into them:
/// - `date`: formatted print date
/// - `title`: document title
/// - `url`: document location
/// - `pageNumber`: current page number
/// - `totalPages`: total pages in the document
/// 
/// For example, `<span class=title></span>` would generate span containing the title.
///  - `footer_template` : HTML template for the print footer. Should use the same format as the `headerTemplate`.
///  - `prefer_css_page_size` : Whether or not to prefer page size as defined by css. Defaults to false,
/// in which case the content will be scaled to fit the paper size.
/// 
/// Returns:  
///  - `data` : Base64-encoded pdf data. Empty if |returnAsStream| is specified. (Encoded as a base64 string when passed over JSON)
/// 
pub fn print_to_pdf(
  callback__,
  landscape landscape: option.Option(Bool),
  display_header_footer display_header_footer: option.Option(Bool),
  print_background print_background: option.Option(Bool),
  scale scale: option.Option(Float),
  paper_width paper_width: option.Option(Float),
  paper_height paper_height: option.Option(Float),
  margin_top margin_top: option.Option(Float),
  margin_bottom margin_bottom: option.Option(Float),
  margin_left margin_left: option.Option(Float),
  margin_right margin_right: option.Option(Float),
  page_ranges page_ranges: option.Option(String),
  header_template header_template: option.Option(String),
  footer_template footer_template: option.Option(String),
  prefer_css_page_size prefer_css_page_size: option.Option(Bool),
) {
  use result__ <- result.try(callback__(
    "Page.printToPDF",
    option.Some(json.object(
      []
      |> utils.add_optional(landscape, fn(inner_value__) {
        #("landscape", json.bool(inner_value__))
      })
      |> utils.add_optional(display_header_footer, fn(inner_value__) {
        #("displayHeaderFooter", json.bool(inner_value__))
      })
      |> utils.add_optional(print_background, fn(inner_value__) {
        #("printBackground", json.bool(inner_value__))
      })
      |> utils.add_optional(scale, fn(inner_value__) {
        #("scale", json.float(inner_value__))
      })
      |> utils.add_optional(paper_width, fn(inner_value__) {
        #("paperWidth", json.float(inner_value__))
      })
      |> utils.add_optional(paper_height, fn(inner_value__) {
        #("paperHeight", json.float(inner_value__))
      })
      |> utils.add_optional(margin_top, fn(inner_value__) {
        #("marginTop", json.float(inner_value__))
      })
      |> utils.add_optional(margin_bottom, fn(inner_value__) {
        #("marginBottom", json.float(inner_value__))
      })
      |> utils.add_optional(margin_left, fn(inner_value__) {
        #("marginLeft", json.float(inner_value__))
      })
      |> utils.add_optional(margin_right, fn(inner_value__) {
        #("marginRight", json.float(inner_value__))
      })
      |> utils.add_optional(page_ranges, fn(inner_value__) {
        #("pageRanges", json.string(inner_value__))
      })
      |> utils.add_optional(header_template, fn(inner_value__) {
        #("headerTemplate", json.string(inner_value__))
      })
      |> utils.add_optional(footer_template, fn(inner_value__) {
        #("footerTemplate", json.string(inner_value__))
      })
      |> utils.add_optional(prefer_css_page_size, fn(inner_value__) {
        #("preferCSSPageSize", json.bool(inner_value__))
      }),
    )),
  ))

  decode__print_to_pdf_response(result__)
  |> result.replace_error(chrome.ProtocolError)
}

/// Reloads given page optionally ignoring the cache.
/// 
/// Parameters:  
///  - `ignore_cache` : If true, browser cache is ignored (as if the user pressed Shift+refresh).
///  - `script_to_evaluate_on_load` : If set, the script will be injected into all frames of the inspected page after reload.
/// Argument will be ignored if reloading dataURL origin.
/// 
/// Returns:  
/// 
pub fn reload(
  callback__,
  ignore_cache ignore_cache: option.Option(Bool),
  script_to_evaluate_on_load script_to_evaluate_on_load: option.Option(String),
) {
  callback__(
    "Page.reload",
    option.Some(json.object(
      []
      |> utils.add_optional(ignore_cache, fn(inner_value__) {
        #("ignoreCache", json.bool(inner_value__))
      })
      |> utils.add_optional(script_to_evaluate_on_load, fn(inner_value__) {
        #("scriptToEvaluateOnLoad", json.string(inner_value__))
      }),
    )),
  )
}

/// Removes given script from the list.
/// 
/// Parameters:  
///  - `identifier`
/// 
/// Returns:  
/// 
pub fn remove_script_to_evaluate_on_new_document(
  callback__,
  identifier identifier: ScriptIdentifier,
) {
  callback__(
    "Page.removeScriptToEvaluateOnNewDocument",
    option.Some(
      json.object([#("identifier", encode__script_identifier(identifier))]),
    ),
  )
}

/// Enable page Content Security Policy by-passing.
/// 
/// Parameters:  
///  - `enabled` : Whether to bypass page CSP.
/// 
/// Returns:  
/// 
pub fn set_bypass_csp(callback__, enabled enabled: Bool) {
  callback__(
    "Page.setBypassCSP",
    option.Some(json.object([#("enabled", json.bool(enabled))])),
  )
}

/// Sets given markup as the document's HTML.
/// 
/// Parameters:  
///  - `frame_id` : Frame id to set HTML for.
///  - `html` : HTML content to set.
/// 
/// Returns:  
/// 
pub fn set_document_content(
  callback__,
  frame_id frame_id: FrameId,
  html html: String,
) {
  callback__(
    "Page.setDocumentContent",
    option.Some(
      json.object([
        #("frameId", encode__frame_id(frame_id)),
        #("html", json.string(html)),
      ]),
    ),
  )
}

/// Controls whether page will emit lifecycle events.
/// 
/// Parameters:  
///  - `enabled` : If true, starts emitting lifecycle events.
/// 
/// Returns:  
/// 
pub fn set_lifecycle_events_enabled(callback__, enabled enabled: Bool) {
  callback__(
    "Page.setLifecycleEventsEnabled",
    option.Some(json.object([#("enabled", json.bool(enabled))])),
  )
}

/// Force the page stop all navigations and pending resource fetches.
/// 
pub fn stop_loading(callback__) {
  callback__("Page.stopLoading", option.None)
}

/// Tries to close page, running its beforeunload hooks, if any.
/// 
pub fn close(callback__) {
  callback__("Page.close", option.None)
}

/// Intercept file chooser requests and transfer control to protocol clients.
/// When file chooser interception is enabled, native file chooser dialog is not shown.
/// Instead, a protocol event `Page.fileChooserOpened` is emitted.
/// 
/// Parameters:  
///  - `enabled`
/// 
/// Returns:  
/// 
pub fn set_intercept_file_chooser_dialog(callback__, enabled enabled: Bool) {
  callback__(
    "Page.setInterceptFileChooserDialog",
    option.Some(json.object([#("enabled", json.bool(enabled))])),
  )
}
