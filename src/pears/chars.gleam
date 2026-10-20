import gleam/int
import gleam/list
import gleam/string
import pears.{
  type ParseError, type ParseResult, type Parser, UnexpectedEndOfInput,
  UnexpectedToken, ok,
}
import pears/combinators.{hidden, just, labelled, many0, many1, map, satisfying}
import pears/input.{type Input, Input}

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
  |> labelled("whitespace")
}

/// Parses zero or more whitespace characters. Hidden from error messages.
pub fn whitespace0() -> Parser(Char, List(Char)) {
  hidden(many0(whitespace()))
}

/// Parses one or more whitespace characters.
pub fn whitespace1() -> Parser(Char, List(Char)) {
  many1(whitespace())
}

/// Parses a given character.
pub fn char(c: Char) -> Parser(Char, Char) {
  just(c)
}

/// Parses a given string. Errors point at the first character that doesn't match.
pub fn string(str: String) -> Parser(Char, String) {
  let chars = string.to_graphemes(str)
  fn(in: Input(Char)) { do_string(in, chars, str) }
}

fn do_string(
  in: Input(Char),
  chars: List(Char),
  str: String,
) -> ParseResult(Char, String) {
  case chars, in.tokens {
    [], _ -> ok(in, str)
    [char, ..rest], [token, ..tokens] if char == token ->
      do_string(Input(tokens, in.cursor + 1), rest, str)
    _, [token, ..] ->
      Error(UnexpectedToken(in.cursor, [string.inspect(str)], token))
    _, [] -> Error(UnexpectedEndOfInput(in.cursor, [string.inspect(str)]))
  }
}

/// Parses a digit in the range 0-9.
pub fn digit() -> Parser(Char, Char) {
  satisfying(fn(c) {
    case c {
      "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
      _ -> False
    }
  })
  |> labelled("digit")
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

/// Returns the 1-based line and column of the character at `position` in `source`.
pub fn line_column(source: String, position: Int) -> #(Int, Int) {
  source
  |> string.to_graphemes()
  |> list.take(position)
  |> list.fold(#(1, 1), fn(acc, char) {
    case char {
      "\n" | "\r\n" -> #(acc.0 + 1, 1)
      _ -> #(acc.0, acc.1 + 1)
    }
  })
}

/// Formats a parse error with the line and column in `source`, the parsed string,
/// e.g. `line 2, column 4: expected "," or "]", found "x"`.
pub fn format_error(error: ParseError(Char), source: String) -> String {
  let #(line, column) = line_column(source, error.position)
  "line "
  <> int.to_string(line)
  <> ", column "
  <> int.to_string(column)
  <> ": "
  <> pears.error_message(error)
}
