//// This module defines the `Input(i)` type that represents a list of tokens that can be consumed by a parser.
//// It also provides some helper functions for working with `Input(i)`.

import gleam/list
import gleam/option.{type Option, None, Some}

/// Represents the tokens that are yet to be consumed by a parser, along with a cursor
/// indicating how many tokens have been consumed so far.
pub type Input(i) {
  Input(tokens: List(i), cursor: Int)
}

pub fn get(input: Input(a)) -> Option(a) {
  case input.tokens {
    [] -> None
    [token, ..] -> Some(token)
  }
}

pub fn get_n(input: Input(a), n: Int) -> List(a) {
  list.take(input.tokens, n)
}

pub fn next(input: Input(a)) -> Input(a) {
  case input.tokens {
    [] -> input
    [_, ..rest] -> Input(tokens: rest, cursor: input.cursor + 1)
  }
}

pub fn next_n(input: Input(a), n: Int) -> Input(a) {
  case n <= 0, input.tokens {
    True, _ | _, [] -> input
    False, [_, ..rest] ->
      next_n(Input(tokens: rest, cursor: input.cursor + 1), n - 1)
  }
}

/// Returns true if the input has been fully consumed
pub fn at_end(input: Input(a)) -> Bool {
  input.tokens == []
}
