import gleam/int
import gleam/result
import gleeunit/should
import helpers.{should_fail_with, should_not_parse, should_parse}
import pears.{Custom, UnexpectedToken, parse_string_all}
import pears/chars.{
  alphanumeric, case_insensitive, float, hex_digit, integer, letter, lexeme,
  line_comment, natural, string, string_literal,
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
