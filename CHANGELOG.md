## [2.2.3] 2024-06-08

- Add `launch_window` function to launch browser in headful mode

## [2.2.2] 2024-06-07

This update brings basic utilities for integration testing and some conveniences in the high level `chrobot` module

- Add `click` and `focus` functions
- Add `press_key`, `type_text`, and text input related functions

## [2.1.2] 2024-05-29  

- Improve message parsing performance A LOT 🚀
  - This should have a big impact on the speed of generating PDFs and taking screenshots

## [2.1.1] 2024-05-25

- Rename the install module to browser_install 

## [2.1.0] 2024-05-25

- Allow setting launch config through environment
- Make logging prettier
- Add browser installation script

## [2.0.0] 2024-05-17

- **Breaking Change:** Added `log_level` to `chrome.BrowserConfig`, this means any `launch_with_config` calls must 
be amended with this extra parameter

- Adjusted browser logging behaviour

## [1.2.0] 2024-05-16

- Move codegen scripts to `/test` to fix published package 

## [1.1.0] 2024-05-16

- Remove unused `glexec` dependency
- Trying to pass a dynamic value to an enocder now logs a warning 

## [1.0.0] 2024-05-16

Initial release