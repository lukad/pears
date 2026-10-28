import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pears.{
  type ParseError, type Parser, type StepResult, UnexpectedEndOfInput,
  UnexpectedToken, new_parser, ok,
}
import pears/combinators.{
  between, choice, exactly, hidden, label, many0, many1, map, none_of, one_of,
  optional, or, pair, recognize, replace, satisfying, skip_then, succeed, then,
  then_skip, token, try_map,
}
import pears/input.{type Input}

const ascii_letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

const hex_digits = "0123456789abcdefABCDEF"

const max_float = 1.7976931348623157e308

const min_float = -1.7976931348623157e308

/// A grapheme is a user-perceived character.
pub type Char =
  String

/// Parses a character if it is whitespace according to the Unicode standard.
pub fn whitespace() -> Parser(Char, Char) {
  satisfying(fn(c) { string.trim(c) == "" })
  |> label("whitespace")
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
  then_skip(parser, whitespace0())
}

/// Parses a given string. Errors point at the first character that doesn't match.
pub fn string(str: String) -> Parser(Char, String) {
  let chars = string.to_graphemes(str)
  new_parser(fn(in: Input(Char)) { do_string(in, chars, str) })
}

fn do_string(
  in: Input(Char),
  chars: List(Char),
  str: String,
) -> StepResult(Char, String) {
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
  new_parser(fn(in: Input(Char)) { do_case_insensitive(in, chars, str, []) })
}

fn do_case_insensitive(
  in: Input(Char),
  chars: List(Char),
  str: String,
  matched: List(Char),
) -> StepResult(Char, String) {
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
  |> label("letter")
}

/// Parses an ASCII letter or a digit.
pub fn alphanumeric() -> Parser(Char, Char) {
  satisfying(fn(c) { string.contains(ascii_letters, c) || is_digit(c) })
  |> label("letter or digit")
}

/// Parses a hexadecimal digit, 0-9, a-f or A-F.
pub fn hex_digit() -> Parser(Char, Char) {
  satisfying(string.contains(hex_digits, _))
  |> label("hex digit")
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
  |> label("digit")
}

/// Parses a non-negative integer consisting of one or more digits. On JavaScript,
/// integers too large to be represented exactly fail with a custom error.
pub fn natural() -> Parser(Char, Int) {
  many1(digit())
  |> try_map(fn(digits) {
    let digits = string.concat(digits)
    let assert Ok(number) = int.parse(digits)
    // JavaScript integers lose precision above 2^53
    case int.to_string(number) == trim_leading_zeros(digits) {
      True -> Ok(number)
      False -> Error("integer out of range")
    }
  })
}

fn trim_leading_zeros(digits: String) -> String {
  case digits {
    "0" <> rest if rest != "" -> trim_leading_zeros(rest)
    _ -> digits
  }
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
    use sign <- then(optional(token("-")))
    use number <- then(natural())
    case sign {
      Some(_) -> succeed(-number)
      None -> succeed(number)
    }
  }
  |> label("integer")
}

/// Parses a number with a fractional part and an optional exponent, like
/// `-1.5` or `2.0e10`. Numbers out of range fail with a custom error.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("-1.5e3", float()) == Ok(-1500.0)
/// ```
pub fn float() -> Parser(Char, Float) {
  let digits = many1(digit())
  let exponent =
    pair(one_of(["e", "E"]), pair(optional(one_of(["+", "-"])), digits))
  recognize(pair(
    pair(optional(token("-")), digits),
    pair(pair(token("."), digits), optional(exponent)),
  ))
  |> try_map(fn(chars) {
    case float.parse(string.concat(chars)) {
      // Erlang fails to parse floats out of range, JavaScript returns Infinity
      Ok(value) if value <=. max_float && value >=. min_float -> Ok(value)
      _ -> Error("float out of range")
    }
  })
  |> label("float")
}

/// Parses a double-quoted string with JSON-style escapes (`\"`, `\\`, `\/`,
/// `\b`, `\f`, `\n`, `\r`, `\t` and `\uXXXX`, including surrogate pairs) and
/// returns its contents.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("\"a\\nb\"", string_literal()) == Ok("a\nb")
/// ```
pub fn string_literal() -> Parser(Char, String) {
  let hex4 =
    exactly(hex_digit(), 4)
    |> map(fn(digits) {
      let assert Ok(code) = int.base_parse(string.concat(digits), 16)
      code
    })
  let unicode =
    {
      use high <- then(skip_then(token("u"), hex4))
      case high >= 0xD800 && high <= 0xDBFF {
        False -> succeed(high)
        // a high surrogate is only valid when followed by an escaped low surrogate
        True -> {
          use low <- then(optional(skip_then(string("\\u"), hex4)))
          case low {
            Some(low) if low >= 0xDC00 && low <= 0xDFFF ->
              succeed(0x10000 + { high - 0xD800 } * 0x400 + { low - 0xDC00 })
            _ -> succeed(high)
          }
        }
      }
    }
    |> try_map(fn(code) {
      string.utf_codepoint(code)
      |> result.map(fn(codepoint) { string.from_utf_codepoints([codepoint]) })
      |> result.replace_error("invalid code point")
    })
  let escape =
    skip_then(
      token("\\"),
      choice([
        token("\""),
        token("\\"),
        token("/"),
        replace(token("b"), "\u{0008}"),
        replace(token("f"), "\u{000C}"),
        replace(token("n"), "\n"),
        replace(token("r"), "\r"),
        replace(token("t"), "\t"),
        unicode,
      ]),
    )
  or(none_of(["\"", "\\"]), escape)
  |> many0()
  |> map(string.concat)
  |> between(token("\""), token("\""))
  |> label("string")
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
  skip_then(string(start), many0(none_of(["\n", "\r\n"])))
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
