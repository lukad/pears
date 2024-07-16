//// This module defines the `Input(i)` type that represents a list of tokens that can be consumed by a parser.
//// It also provides some helper functions for working with `Input(i)`.

import gleam/iterator
import gleam/list
import gleam/option.{type Option}

/// Represents a list of tokens that can be consumed by a parser, along with a cursor indicating the current position.
pub type Input(i) {
  Input(tokens: List(i), cursor: Int)
}

pub fn get(input: Input(a)) -> Option(a) {
  input.tokens
  |> iterator.from_list()
  |> iterator.at(input.cursor)
  |> option.from_result()
}

pub fn get_n(input: Input(a), n: Int) -> List(a) {
  input.tokens
  |> list.drop(input.cursor)
  |> list.take(n)
}

pub fn next(input: Input(a)) -> Input(a) {
  Input(..input, cursor: input.cursor + 1)
}

pub fn next_n(input: Input(a), n: Int) -> Input(a) {
  Input(..input, cursor: input.cursor + n)
}

/// Returns true if the input has been fully consumed
pub fn at_end(input: Input(a)) -> Bool {
  input.cursor >= list.length(input.tokens)
}
