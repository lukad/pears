//// This module defines the `Input(i)` type that represents a list of tokens that can be consumed by a parser.
//// It also provides some helper functions for working with `Input(i)`.

import gleam/list
import gleam/option.{type Option, None, Some}

/// The tokens that are yet to be consumed by a parser, along with the number of
/// tokens consumed so far.
pub opaque type Input(i) {
  Input(tokens: List(i), position: Int)
}

/// Creates an input from a list of tokens.
pub fn new(tokens: List(i)) -> Input(i) {
  Input(tokens, 0)
}

/// Returns the tokens that haven't been consumed yet.
pub fn tokens(input: Input(i)) -> List(i) {
  input.tokens
}

/// Returns the number of tokens consumed so far.
pub fn position(input: Input(i)) -> Int {
  input.position
}

/// Returns the next token, if any.
pub fn get(input: Input(a)) -> Option(a) {
  case input.tokens {
    [] -> None
    [token, ..] -> Some(token)
  }
}

/// Returns up to `n` next tokens.
pub fn get_n(input: Input(a), n: Int) -> List(a) {
  list.take(input.tokens, n)
}

/// Consumes the next token.
pub fn next(input: Input(a)) -> Input(a) {
  case input.tokens {
    [] -> input
    [_, ..rest] -> Input(tokens: rest, position: input.position + 1)
  }
}

/// Consumes up to `n` tokens.
pub fn next_n(input: Input(a), n: Int) -> Input(a) {
  case n <= 0, input.tokens {
    True, _ | _, [] -> input
    False, [_, ..rest] ->
      next_n(Input(tokens: rest, position: input.position + 1), n - 1)
  }
}

/// Returns true if the input has been fully consumed
pub fn at_end(input: Input(a)) -> Bool {
  input.tokens == []
}
