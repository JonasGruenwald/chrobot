import chrobot
import gleam/option.{type Option, None, Some}

const default_timeout = 5000

type SpecialTarget {
  Button
  Input(input_type: String)
  TextArea
  Select
  Anchor
}

pub opaque type Locator {
  Locator(
    page: chrobot.Page,
    timeout: Int,
    special_target: Option(SpecialTarget),
    tag_name: Option(String),
    placeholder: Option(String),
    attributes: List(#(String, String)),
    classes: List(String),
    id: Option(String),
  )
}

pub fn new(page: chrobot.Page) -> Locator {
  Locator(
    page:,
    timeout: default_timeout,
    special_target: None,
    tag_name: None,
    placeholder: None,
    attributes: [],
    classes: [],
    id: None,
  )
}

pub fn timeout(locator: Locator, timeout: Int) -> Locator {
  Locator(..locator, timeout:)
}

pub fn button(locator: Locator) -> Locator {
  Locator(..locator, special_target: Some(Button))
}

pub fn input(locator: Locator, input_type: String) -> Locator {
  Locator(..locator, special_target: Some(Input(input_type)))
}

pub fn text_area(locator: Locator) -> Locator {
  Locator(..locator, special_target: Some(TextArea))
}

pub fn select(locator: Locator) -> Locator {
  Locator(..locator, special_target: Some(Select))
}

pub fn anchor(locator: Locator) -> Locator {
  Locator(..locator, special_target: Some(Anchor))
}

pub fn tag_name(locator: Locator, tag_name: String) -> Locator {
  Locator(..locator, tag_name: Some(tag_name))
}

pub fn placeholder(locator: Locator, placeholder: String) -> Locator {
  Locator(..locator, placeholder: Some(placeholder))
}

pub fn attribute(locator: Locator, name: String, value: String) -> Locator {
  Locator(..locator, attributes: [#(name, value), ..locator.attributes])
}

pub fn class(locator: Locator, class_name: String) -> Locator {
  Locator(..locator, classes: [class_name, ..locator.classes])
}

pub fn id(locator: Locator, id: String) -> Locator {
  Locator(..locator, id: Some(id))
}
