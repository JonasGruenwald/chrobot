import chrobot
import chrome
import gleam/erlang/process

pub fn main() {
  let assert Ok(browser) = chrobot.launch()

  let my_event_subject = process.new_subject()
  process.send(
    browser,
    chrome.AddListener(my_event_subject, "Target.targetCreated"),
  )

  // While we have the listener, we could call receive on the subject
  // to receive messages

  process.sleep(1000)

  process.send(browser, chrome.RemoveListener(my_event_subject))

  process.sleep(1000)

  let assert Ok(_) = chrobot.quit(browser)
}
