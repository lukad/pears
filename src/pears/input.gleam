import gleam/option.{type Option, None, Some}

/// A grapheme cluster is a user-perceived character
pub type Char =
  String

/// Represents a list of tokens that can be consumed by a parser
pub type Input(i) =
  List(i)

/// Get the head and tail of an input
pub fn get(input: Input(a)) -> Option(#(a, Input(a))) {
  case input {
    [] -> None
    [head, ..tail] -> Some(#(head, tail))
  }
}
