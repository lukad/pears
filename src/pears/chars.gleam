import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pears.{
  type ParseError, type ParseResult, type Parser, UnexpectedEndOfInput,
  UnexpectedToken, ok,
}
import pears/combinators.{
  alt, between, choice, exactly, fail, hidden, just, labelled, left, many0,
  many1, map, maybe, none_of, one_of, pair, recognize, right, satisfying,
  succeed, then, to,
}
import pears/input.{type Input}

const ascii_letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

const hex_digits = "0123456789abcdefABCDEF"

/// A grapheme is a user-perceived character.
pub type Char =
  String

/// Parses a character if it is whitespace according to the Unicode standard.
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

/// Runs the parser and skips any whitespace after it.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("let  ", lexeme(string("let"))) == Ok("let")
/// ```
pub fn lexeme(parser: Parser(Char, a)) -> Parser(Char, a) {
  left(parser, whitespace0())
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
  case chars, input.tokens(in) {
    [], _ -> ok(in, str)
    [char, ..rest], [token, ..] if char == token ->
      do_string(input.next(in), rest, str)
    _, [token, ..] ->
      Error(UnexpectedToken(input.position(in), [string.inspect(str)], token))
    _, [] ->
      Error(UnexpectedEndOfInput(input.position(in), [string.inspect(str)]))
  }
}

/// Parses a given string, ignoring case, and returns the matched input.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("Select", case_insensitive("SELECT")) == Ok("Select")
/// ```
pub fn case_insensitive(str: String) -> Parser(Char, String) {
  let chars = string.to_graphemes(string.lowercase(str))
  fn(in: Input(Char)) { do_case_insensitive(in, chars, str, []) }
}

fn do_case_insensitive(
  in: Input(Char),
  chars: List(Char),
  str: String,
  matched: List(Char),
) -> ParseResult(Char, String) {
  case chars, input.tokens(in) {
    [], _ -> ok(in, matched |> list.reverse |> string.concat)
    [char, ..rest], [token, ..] ->
      case string.lowercase(token) == char {
        True ->
          do_case_insensitive(input.next(in), rest, str, [token, ..matched])
        False ->
          Error(UnexpectedToken(
            input.position(in),
            [string.inspect(str)],
            token,
          ))
      }
    _, [] ->
      Error(UnexpectedEndOfInput(input.position(in), [string.inspect(str)]))
  }
}

/// Parses an ASCII letter, a-z or A-Z.
pub fn letter() -> Parser(Char, Char) {
  satisfying(string.contains(ascii_letters, _))
  |> labelled("letter")
}

/// Parses an ASCII letter or a digit.
pub fn alphanumeric() -> Parser(Char, Char) {
  satisfying(fn(c) { string.contains(ascii_letters, c) || is_digit(c) })
  |> labelled("letter or digit")
}

/// Parses a hexadecimal digit, 0-9, a-f or A-F.
pub fn hex_digit() -> Parser(Char, Char) {
  satisfying(string.contains(hex_digits, _))
  |> labelled("hex digit")
}

fn is_digit(c: Char) -> Bool {
  case c {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

/// Parses a digit in the range 0-9.
pub fn digit() -> Parser(Char, Char) {
  satisfying(is_digit)
  |> labelled("digit")
}

/// Parses a number consisting of one or more digits.
pub fn number() -> Parser(Char, Int) {
  many1(digit())
  |> map(fn(digits) {
    let assert Ok(number) = int.parse(string.concat(digits))
    number
  })
}

/// Parses an integer with an optional leading `-`.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("-42", integer()) == Ok(-42)
/// ```
pub fn integer() -> Parser(Char, Int) {
  {
    use sign <- then(maybe(char("-")))
    use number <- then(number())
    case sign {
      Some(_) -> succeed(-number)
      None -> succeed(number)
    }
  }
  |> labelled("integer")
}

/// Parses a number with a fractional part and an optional exponent, like
/// `-1.5` or `2.0e10`. Fails if the number is out of range on Erlang.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("-1.5e3", float()) == Ok(-1500.0)
/// ```
pub fn float() -> Parser(Char, Float) {
  let digits = many1(digit())
  let exponent =
    pair(one_of(["e", "E"]), pair(maybe(one_of(["+", "-"])), digits))
  let parser = {
    use chars <- then(
      recognize(pair(
        pair(maybe(char("-")), digits),
        pair(pair(char("."), digits), maybe(exponent)),
      )),
    )
    case float.parse(string.concat(chars)) {
      Ok(value) -> succeed(value)
      Error(_) -> fail("float in range")
    }
  }
  labelled(parser, "float")
}

/// Parses a double-quoted string with JSON-style escapes (`\"`, `\\`, `\/`,
/// `\b`, `\f`, `\n`, `\r`, `\t` and `\uXXXX`) and returns its contents.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("\"a\\nb\"", string_literal()) == Ok("a\nb")
/// ```
pub fn string_literal() -> Parser(Char, String) {
  let unicode = {
    use digits <- then(right(char("u"), exactly(hex_digit(), 4)))
    let codepoint =
      int.base_parse(string.concat(digits), 16)
      |> result.try(string.utf_codepoint)
    case codepoint {
      Ok(codepoint) -> succeed(string.from_utf_codepoints([codepoint]))
      Error(_) -> fail("valid code point")
    }
  }
  let escape =
    right(
      char("\\"),
      choice([
        char("\""),
        char("\\"),
        char("/"),
        to(char("b"), "\u{0008}"),
        to(char("f"), "\u{000C}"),
        to(char("n"), "\n"),
        to(char("r"), "\r"),
        to(char("t"), "\t"),
        unicode,
      ]),
    )
  alt(none_of(["\"", "\\"]), escape)
  |> many0()
  |> map(string.concat)
  |> between(char("\""), char("\""))
  |> labelled("string")
}

/// Parses `start` and the rest of the line, returning the text after `start`.
/// The line break isn't consumed.
///
/// ```gleam
/// import pears
///
/// let assert Ok(parsed) = pears.parse_string("// hi\nx", line_comment("//"))
/// assert parsed.value == " hi"
/// ```
pub fn line_comment(start: String) -> Parser(Char, String) {
  right(string(start), many0(none_of(["\n", "\r\n"])))
  |> map(string.concat)
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
