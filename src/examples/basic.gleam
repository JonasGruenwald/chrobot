////
////  Run this example with `gleam run -m chrobot/examples/basic`
//// 

// import chrome
// import gleam/erlang/process
// import gleam/io
// import gleam/option as o
// import protocol/target

// pub fn main() {
//   let assert Ok(browser_subject) = chrome.launch()
//   use <- chrome.defer_quit(browser_subject)
//   io.print("Browser launched ")
//   let assert Ok(target_response) =
//     target.create_target(
//       browser_subject,
//       "https://gleam.run/",
//       o.None,
//       o.None,
//       o.None,
//       o.None,
//     )
//   io.debug(#("Target created ", target_response.target_id))
// }
