import pears/input
import pears.{type Parsed, type Parser, Parsed, parse_string}
import gleeunit/should

pub fn should_be_at_end(parsed: Parsed(i, a)) -> Parsed(i, a) {
  parsed.input
  |> input.at_end()
  |> should.be_true()
  parsed
}

pub fn should_be_value(parsed: Parsed(i, a), value: a) -> Parsed(i, a) {
  parsed.value
  |> should.equal(value)
  parsed
}

pub fn should_parse(
  parser: Parser(String, a),
  input: String,
  expected: a,
) -> Parser(String, a) {
  input
  |> parse_string(parser)
  |> should.be_ok()
  |> should_be_value(expected)
  parser
}

pub fn should_not_parse(
  parser: Parser(String, a),
  input: String,
) -> Parser(String, a) {
  input
  |> parse_string(parser)
  |> should.be_error()
  parser
}
