//// This module defines the `Input(i)` type that represents a list of tokens that can be consumed by a parser.
//// It also provides some helper functions for working with `Input(i)`.

import gleam/option.{type Option, None, Some}

/// Represents a list of tokens that can be consumed by a parser.
pub type Input(i) =
  List(i)

/// Get the head and tail of an input.
///
/// ### Examples
///
/// ```gleam
/// get(Input([1, 2, 3]))
/// // => Some(#(1, Input([2, 3])))
/// ```
///
/// ```gleam
/// get(Input([]))
/// // => None
/// ```
pub fn get(input: Input(a)) -> Option(#(a, Input(a))) {
  case input {
    [] -> None
    [head, ..tail] -> Some(#(head, tail))
  }
}

/// Returns true if the input has been fully consumed
pub fn at_end(input: Input(a)) -> Bool {
  case input {
    [] -> True
    _ -> False
  }
}
