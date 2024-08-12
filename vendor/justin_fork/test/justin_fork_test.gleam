import gleam/list
import gleeunit
import justin_fork as justin

pub fn main() {
  gleeunit.main()
}

const snake_cases = [
  #("", ""),
  #("snake case", "snake_case"),
  #("snakeCase", "snake_case"),
  #("SNAKECase", "snake_case"),
  #("Snake-Case", "snake_case"),
  #("Snake_Case", "snake_case"),
  #("SnakeCase", "snake_case"),
  #("Snake.Case", "snake_case"),
  #("SNAKE_CASE", "snake_case"),
  #("--snake-case--", "snake_case"),
  #("snake#case", "snake_case"),
  #("snake?!case", "snake_case"),
  #("snake\tcase", "snake_case"),
  #("snake\ncase", "snake_case"),
  #("λambdaΛambda", "λambda_λambda"),
]

const camel_cases = [
  #("", ""),
  #("snake case", "snakeCase"),
  #("snakeCase", "snakeCase"),
  #("Snake-Case", "snakeCase"),
  #("SNAKECase", "snakeCase"),
  #("Snake_Case", "snakeCase"),
  #("SnakeCase", "snakeCase"),
  #("Snake.Case", "snakeCase"),
  #("SNAKE_CASE", "snakeCase"),
  #("--snake-case--", "snakeCase"),
  #("snake#case", "snakeCase"),
  #("snake?!case", "snakeCase"),
  #("snake\tcase", "snakeCase"),
  #("snake\ncase", "snakeCase"),
  #("λambda_λambda", "λambdaΛambda"),
]

const pascal_cases = [
  #("", ""),
  #("snake case", "SnakeCase"),
  #("snakeCase", "SnakeCase"),
  #("SNAKECase", "SnakeCase"),
  #("Snake-Case", "SnakeCase"),
  #("Snake_Case", "SnakeCase"),
  #("SnakeCase", "SnakeCase"),
  #("Snake.Case", "SnakeCase"),
  #("SNAKE_CASE", "SnakeCase"),
  #("--snake-case--", "SnakeCase"),
  #("snake#case", "SnakeCase"),
  #("snake?!case", "SnakeCase"),
  #("snake\tcase", "SnakeCase"),
  #("snake\ncase", "SnakeCase"),
  #("λambda_λambda", "ΛambdaΛambda"),
]

const kebab_cases = [
  #("", ""),
  #("snake case", "snake-case"),
  #("snakeCase", "snake-case"),
  #("SNAKECase", "snake-case"),
  #("Snake-Case", "snake-case"),
  #("Snake_Case", "snake-case"),
  #("SnakeCase", "snake-case"),
  #("Snake.Case", "snake-case"),
  #("SNAKE_CASE", "snake-case"),
  #("--snake-case--", "snake-case"),
  #("snake#case", "snake-case"),
  #("snake?!case", "snake-case"),
  #("snake\tcase", "snake-case"),
  #("snake\ncase", "snake-case"),
  #("λambda_λambda", "λambda-λambda"),
]

const sentence_cases = [
  #("", ""),
  #("snake case", "Snake case"),
  #("snakeCase", "Snake case"),
  #("SNAKECase", "Snake case"),
  #("Snake-Case", "Snake case"),
  #("Snake_Case", "Snake case"),
  #("SnakeCase", "Snake case"),
  #("Snake.Case", "Snake case"),
  #("SNAKE_CASE", "Snake case"),
  #("--snake-case--", "Snake case"),
  #("snake#case", "Snake case"),
  #("snake?!case", "Snake case"),
  #("snake\tcase", "Snake case"),
  #("snake\ncase", "Snake case"),
  #("λambda_λambda", "Λambda λambda"),
]

fn run_cases(cases: List(#(String, String)), function: fn(String) -> String) {
  use #(in, out) <- list.each(cases)
  let real = function(in)
  case real == out {
    True -> Nil
    False -> panic as { in <> " should be " <> out <> ", got " <> real }
  }
}

pub fn snake_test() {
  run_cases(snake_cases, justin.snake_case)
}

pub fn camel_test() {
  run_cases(camel_cases, justin.camel_case)
}

pub fn pascal_test() {
  run_cases(pascal_cases, justin.pascal_case)
}

pub fn kebab_test() {
  run_cases(kebab_cases, justin.kebab_case)
}

pub fn sentence_test() {
  run_cases(sentence_cases, justin.sentence_case)
}
