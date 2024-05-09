//// > ⚙️  This module was generated from the Chrome DevTools Protocol version **1.3**
//// ## Emulation Domain  
////
//// This domain emulates different environments for the page.  
////
//// [📖   View this domain on the DevTools Protocol API Docs](https://chromedevtools.github.io/devtools-protocol/1-3/Emulation/)

// ---------------------------------------------------------------------------
// |  !!!!!!   This is an autogenerated file - Do not edit manually  !!!!!!  |
// | Run ` gleam run -m scripts/generate_protocol_bindings.sh` to regenerate.|  
// ---------------------------------------------------------------------------

import protocol/dom
import protocol/page
import protocol/runtime

/// Screen orientation.
pub type ScreenOrientation {
  ScreenOrientation(type_: ScreenOrientationType, angle: Int)
}

/// This type is not part of the protocol spec, it has been generated dynamically 
/// to represent the possible values of the enum property `type` of `ScreenOrientation`
pub type ScreenOrientationType {
  ScreenOrientationTypePortraitPrimary
  ScreenOrientationTypePortraitSecondary
  ScreenOrientationTypeLandscapePrimary
  ScreenOrientationTypeLandscapeSecondary
}

pub type DisplayFeature {
  DisplayFeature(
    orientation: DisplayFeatureOrientation,
    offset: Int,
    mask_length: Int,
  )
}

/// This type is not part of the protocol spec, it has been generated dynamically 
/// to represent the possible values of the enum property `orientation` of `DisplayFeature`
pub type DisplayFeatureOrientation {
  DisplayFeatureOrientationVertical
  DisplayFeatureOrientationHorizontal
}

pub type DevicePosture {
  DevicePosture(type_: DevicePostureType)
}

/// This type is not part of the protocol spec, it has been generated dynamically 
/// to represent the possible values of the enum property `type` of `DevicePosture`
pub type DevicePostureType {
  DevicePostureTypeContinuous
  DevicePostureTypeFolded
}

pub type MediaFeature {
  MediaFeature(name: String, value: String)
}
