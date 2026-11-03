import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import helpers.{should_fail_with, should_not_parse, should_parse}
import pears.{Custom, UnexpectedToken, parse_string_all}
import pears/chars.{
  alphanumeric, case_insensitive, float, hex_digit, integer, letter, lexeme,
  line_comment, natural, newline, string, string_literal, whitespace,
}
import pears/combinators.{pair}

pub fn letter_test() {
  letter()
  |> should_parse("a", "a")
  |> should_parse("Z", "Z")
  |> should_not_parse("é")
  |> should_fail_with("1", UnexpectedToken(0, ["letter"], "1"))
}

pub fn alphanumeric_test() {
  alphanumeric()
  |> should_parse("a", "a")
  |> should_parse("7", "7")
  |> should_fail_with("_", UnexpectedToken(0, ["letter or digit"], "_"))
}

pub fn hex_digit_test() {
  hex_digit()
  |> should_parse("f", "f")
  |> should_parse("A", "A")
  |> should_parse("9", "9")
  |> should_fail_with("g", UnexpectedToken(0, ["hex digit"], "g"))
}

pub fn character_classes_reject_other_tokens_test() {
  // tokens passed to `pears.parse` don't have to be single characters
  use parser <- list.each([letter(), alphanumeric(), hex_digit()])
  use token <- list.each(["ab", "", "a\u{0301}"])
  pears.parse([token], parser) |> should.be_error()
}

pub fn integer_test() {
  integer()
  |> should_parse("0", 0)
  |> should_parse("-0", 0)
  |> should_parse("123", 123)
  |> should_parse("-123", -123)
  |> should_fail_with("x", UnexpectedToken(0, ["integer"], "x"))
  |> should_fail_with("-x", UnexpectedToken(1, ["digit"], "x"))
}

pub fn float_test() {
  parse_string_all("1.5", float()) |> should.equal(Ok(1.5))
  parse_string_all("-0.25", float()) |> should.equal(Ok(-0.25))
  parse_string_all("1.5E3", float()) |> should.equal(Ok(1500.0))
  parse_string_all("1.5e+3", float()) |> should.equal(Ok(1500.0))
  parse_string_all("1.5e-3", float()) |> should.equal(Ok(0.0015))

  parse_string_all("1", float()) |> should.be_error()
  parse_string_all("1.", float()) |> should.be_error()
  parse_string_all(".5", float()) |> should.be_error()
  parse_string_all("1.5e", float()) |> should.be_error()
}

pub fn newline_test() {
  newline()
  |> should_parse("\n", "\n")
  |> should_parse("\r\n", "\r\n")
  |> should_not_parse("\r")
  |> should_fail_with("x", UnexpectedToken(0, ["newline"], "x"))
}

pub fn whitespace_test() {
  // Pattern_White_Space and CRLF as one grapheme, without U+200E and U+200F
  // which `string.trim` only removes on Erlang
  [
    "\t", "\n", "\u{000B}", "\u{000C}", "\r", "\r\n", " ", "\u{0085}",
    "\u{2028}", "\u{2029}",
  ]
  |> list.each(fn(c) { whitespace() |> should_parse(c, c) })

  // nonbreaking and zero width characters and a space with a combining mark
  ["a", "\u{00A0}", "\u{200B}", "\u{3000}", "\u{FEFF}", " \u{0301}"]
  |> list.each(fn(c) { whitespace() |> should_not_parse(c) })
}

pub fn string_literal_test() {
  string_literal()
  |> should_parse("\"\"", "")
  |> should_parse("\"abc\"", "abc")
  |> should_parse(
    "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\"",
    "\"\\/\u{0008}\u{000C}\n\r\t",
  )
  |> should_parse("\"\\u0041\\u00e9\"", "Aé")
  |> should_parse("\"👋\"", "👋")
  |> should_not_parse("\"abc")
  |> should_not_parse("\"\\x\"")
  |> should_not_parse("\"\\uD800\"")
  |> should_fail_with("x", UnexpectedToken(0, ["string"], "x"))
}

pub fn case_insensitive_test() {
  case_insensitive("abc")
  |> should_parse("abc", "abc")
  |> should_parse("AbC", "AbC")
  |> should_fail_with("aBx", UnexpectedToken(2, ["\"abc\""], "x"))
}

pub fn line_comment_test() {
  line_comment("#")
  |> should_parse("#", "")
  |> should_parse("# hi\nnext", " hi")
  |> should_parse("# hi\r\nnext", " hi")
  |> should_not_parse("// hi")
}

pub fn lexeme_test() {
  lexeme(string("a"))
  |> should_parse("a", "a")
  |> should_parse("a \n\t", "a")

  pair(lexeme(string("a")), string("b"))
  |> should_parse("a  b", #("a", "b"))
}

pub fn natural_test() {
  natural()
  |> should_parse("0", 0)
  |> should_parse("007", 7)

  // too large for JavaScript to represent exactly
  let result =
    parse_string_all("9007199254740993", natural())
    |> result.map(int.to_string)
  let exact_or_error =
    result == Ok("9007199254740993")
    || result == Error(Custom(0, "integer out of range"))
  exact_or_error |> should.be_true()
}

pub fn integer_too_large_for_any_target_test() {
  // over the size limit of Erlang integers
  let digits = string.repeat("9", 1_400_000)

  parse_string_all(digits, natural())
  |> should.equal(Error(Custom(0, "integer out of range")))

  parse_string_all("-" <> digits, integer())
  |> should.equal(Error(Custom(1, "integer out of range")))
}

pub fn float_out_of_range_test() {
  parse_string_all("1.0e999", float())
  |> should.equal(Error(Custom(0, "float out of range")))

  parse_string_all("-1.0e999", float())
  |> should.equal(Error(Custom(0, "float out of range")))
}

pub fn surrogate_pair_test() {
  string_literal()
  |> should_parse("\"\\uD83D\\uDE00\"", "😀")
  |> should_fail_with("\"\\uD83D\"", Custom(2, "invalid code point"))
  |> should_fail_with("\"\\uD83D\\u0041\"", Custom(2, "invalid code point"))
  |> should_fail_with("\"\\uDE00\"", Custom(2, "invalid code point"))
}

pub fn string_literal_combining_marks_test() {
  let expected = ["closing quote"]

  string_literal()
  |> should_parse("\"e\u{0301}\"", "e\u{0301}")
  // a combining mark forms a single grapheme with the quote or backslash before it
  |> should_fail_with(
    "\"abc\"\u{0301}",
    UnexpectedToken(4, expected, "\"\u{0301}"),
  )
  |> should_fail_with(
    "\"\\\u{0301}\"",
    UnexpectedToken(1, expected, "\\\u{0301}"),
  )
}
