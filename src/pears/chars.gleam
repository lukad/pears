import gleam/int
import gleam/string
import gleam/list
import pears.{type Parser, ParseError, ok}
import pears/input.{type Input}
import pears/combinators.{just, many0, many1, map, one_of, satisfying}

/// Build an `Input(Char)` from a string.
pub fn input(s: String) -> Input(Char) {
  string.to_graphemes(s)
}

/// A grapheme is a user-perceived character.
pub type Char =
  String

pub fn whitespace() -> Parser(Char, Char) {
  satisfying(fn(c) { string.trim(c) == "" })
}

pub fn whitespace0() -> Parser(Char, List(Char)) {
  many0(whitespace())
}

pub fn whitespace1() -> Parser(Char, List(Char)) {
  many1(whitespace())
}

pub fn char(c: Char) -> Parser(Char, Char) {
  just(c)
}

pub fn string(str: String) -> Parser(Char, String) {
  fn(input: Input(Char)) {
    let s = string.to_graphemes(str)
    let length = list.length(s)
    case list.length(input) >= length {
      True -> {
        let candidate = list.take(input, length)
        case candidate == s {
          True -> ok(list.drop(input, length), str)
          False -> Error(ParseError(input, [str]))
        }
      }
      False -> Error(ParseError(input, [str]))
    }
  }
}

pub fn digit() -> Parser(Char, Char) {
  one_of(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])
}

pub fn number() -> Parser(Char, Int) {
  many1(digit())
  |> map(fn(digits) {
    list.fold(digits, 0, fn(acc, digit) {
      let assert Ok(digit) = int.parse(digit)
      acc * 10 + digit
    })
  })
}
