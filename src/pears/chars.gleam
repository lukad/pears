import gleam/int
import gleam/string
import gleam/list
import pears.{type Parser, UnexpectedEndOfInput, UnexpectedToken, ok}
import pears/input.{type Input, Input}
import pears/combinators.{just, many0, many1, map, one_of, satisfying}

/// Creates an `Input(Char)` from a string.
pub fn input(s: String) -> Input(Char) {
  let tokens = string.to_graphemes(s)
  Input(tokens, 0)
}

/// A grapheme is a user-perceived character.
pub type Char =
  String

/// Parses a character if is whitespace according to the Unicode standard.
pub fn whitespace() -> Parser(Char, Char) {
  satisfying(fn(c) { string.trim(c) == "" })
}

/// Parses zero or more whitespace characters.
pub fn whitespace0() -> Parser(Char, List(Char)) {
  many0(whitespace())
}

/// Parses one or more whitespace characters.
pub fn whitespace1() -> Parser(Char, List(Char)) {
  many1(whitespace())
}

/// Parses a given character.
pub fn char(c: Char) -> Parser(Char, Char) {
  just(c)
}

/// Parses a given string.
pub fn string(str: String) -> Parser(Char, String) {
  fn(in: Input(Char)) {
    let s = string.to_graphemes(str)
    let length = list.length(s)
    let candidate = input.get_n(in, length)
    case candidate == s {
      True -> ok(input.next_n(in, length), str)
      False ->
        case candidate {
          [] -> Error(UnexpectedEndOfInput(in, [str]))
          [head, ..] -> Error(UnexpectedToken(in, [str], head))
        }
    }
  }
}

/// Parses a digit in the range 0-9.
pub fn digit() -> Parser(Char, Char) {
  one_of(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])
}

/// Parses a number consisting of one or more digits.
pub fn number() -> Parser(Char, Int) {
  many1(digit())
  |> map(fn(digits) {
    list.fold(digits, 0, fn(acc, digit) {
      let assert Ok(digit) = int.parse(digit)
      acc * 10 + digit
    })
  })
}
