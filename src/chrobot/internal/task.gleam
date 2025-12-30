//// Lightweight task utility for running async work with timeout.
//// Based on gleam_otp/task from v0.16.1, adapted for gleam_erlang 1.x.

import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/function

pub opaque type Task(value) {
  Task(owner: Pid, pid: Pid, subject: Subject(value))
}

pub type AwaitError {
  Timeout
  Exit(reason: Dynamic)
}

/// Spawn a task process that calls a given function in order to perform some
/// work. The result of this function is sent back to the parent and can be
/// received using the `try_await` function.
pub fn async(work: fn() -> value) -> Task(value) {
  let owner = process.self()
  let subject = process.new_subject()
  let pid = process.spawn(fn() { process.send(subject, work()) })
  Task(owner: owner, pid: pid, subject: subject)
}

/// Wait for the value computed by a task.
///
/// If a value is not received before the timeout has elapsed then an error
/// is returned.
pub fn try_await(task: Task(value), timeout: Int) -> Result(value, AwaitError) {
  assert_owner(task)
  let selector =
    process.new_selector()
    |> process.select_map(task.subject, function.identity)
  case process.selector_receive(from: selector, within: timeout) {
    Ok(x) -> Ok(x)
    Error(Nil) -> Error(Timeout)
  }
}

fn assert_owner(task: Task(a)) -> Nil {
  let self = process.self()
  case task.owner == self {
    True -> Nil
    False ->
      process.send_abnormal_exit(
        self,
        "awaited on a task that does not belong to this process",
      )
  }
}
