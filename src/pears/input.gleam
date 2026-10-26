//// The `Input(i)` type holds the tokens a parser hasn't consumed yet, e.g. the
//// remaining input returned by `pears.parse`.

import gleam/option.{type Option, None, Some}

/// The tokens that are yet to be consumed by a parser, along with the number of
/// tokens consumed so far.
pub opaque type Input(i) {
  Input(tokens: List(i), position: Int)
}

/// Returns the tokens that haven't been consumed yet.
pub fn tokens(input: Input(i)) -> List(i) {
  input.tokens
}

/// Returns the number of tokens consumed so far.
pub fn position(input: Input(i)) -> Int {
  input.position
}

/// Returns true if the input has been fully consumed.
pub fn at_end(input: Input(a)) -> Bool {
  input.tokens == []
}

@internal
pub fn new(tokens: List(i)) -> Input(i) {
  Input(tokens, 0)
}

@internal
pub fn get(input: Input(a)) -> Option(a) {
  case input.tokens {
    [] -> None
    [token, ..] -> Some(token)
  }
}

@internal
pub fn next(input: Input(a)) -> Input(a) {
  case input.tokens {
    [] -> input
    [_, ..rest] -> Input(tokens: rest, position: input.position + 1)
  }
}
