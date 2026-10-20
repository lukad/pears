import gleam/option.{Some}
import gleeunit/should
import helpers.{should_fail_with}
import pears.{UnexpectedEndOfInput, UnexpectedToken}
import pears/chars
import pears/combinators.{
  alt, between, choice, eof, hidden, just, labelled, left, many0, maybe, none_of,
  pair, right, sep_by0, seq,
}

pub fn just_test() {
  just("a")
  |> should_fail_with("b", UnexpectedToken(0, ["\"a\""], "b"))
  |> should_fail_with("", UnexpectedEndOfInput(0, ["\"a\""]))
}

pub fn position_after_consumed_input_test() {
  right(just("a"), just("b"))
  |> should_fail_with("ac", UnexpectedToken(1, ["\"b\""], "c"))
}

pub fn string_points_at_mismatch_test() {
  chars.string("ab")
  |> should_fail_with("ax", UnexpectedToken(1, ["\"ab\""], "x"))
  |> should_fail_with("a", UnexpectedEndOfInput(1, ["\"ab\""]))
  |> should_fail_with("x", UnexpectedToken(0, ["\"ab\""], "x"))
}

pub fn alt_merges_expected_test() {
  alt(just("a"), just("b"))
  |> should_fail_with("c", UnexpectedToken(0, ["\"a\"", "\"b\""], "c"))
  |> should_fail_with("", UnexpectedEndOfInput(0, ["\"a\"", "\"b\""]))
}

pub fn alt_keeps_furthest_error_test() {
  alt(chars.string("ab"), chars.string("x"))
  |> should_fail_with("ac", UnexpectedToken(1, ["\"ab\""], "c"))
}

pub fn choice_merges_expected_test() {
  choice([just("a"), just("b"), just("a")])
  |> should_fail_with("c", UnexpectedToken(0, ["\"a\"", "\"b\""], "c"))
}

pub fn choice_keeps_furthest_error_test() {
  choice([seq([just("a"), just("b"), just("c")]), seq([just("x")])])
  |> should_fail_with("abx", UnexpectedToken(2, ["\"c\""], "x"))
}

pub fn empty_choice_test() {
  choice([])
  |> should_fail_with("a", UnexpectedToken(0, [], "a"))
}

pub fn labelled_test() {
  labelled(just("a"), "letter a")
  |> should_fail_with("b", UnexpectedToken(0, ["letter a"], "b"))
  |> should_fail_with("", UnexpectedEndOfInput(0, ["letter a"]))

  // errors after consuming input are more specific and kept as is
  labelled(chars.string("ab"), "keyword")
  |> should_fail_with("ax", UnexpectedToken(1, ["\"ab\""], "x"))
}

pub fn eof_test() {
  left(just("a"), eof())
  |> should_fail_with("ab", UnexpectedToken(1, ["end of input"], "b"))
}

pub fn none_of_test() {
  none_of(["a"])
  |> should_fail_with("a", UnexpectedToken(0, [], "a"))
}

pub fn chars_labels_test() {
  chars.digit()
  |> should_fail_with("x", UnexpectedToken(0, ["digit"], "x"))

  chars.whitespace()
  |> should_fail_with("x", UnexpectedToken(0, ["whitespace"], "x"))
}

pub fn format_error_test() {
  UnexpectedToken(3, ["\",\"", "\"]\""], "x")
  |> pears.format_error()
  |> should.equal("position 3: expected \",\" or \"]\", found \"x\"")

  UnexpectedEndOfInput(0, ["\"a\"", "\"b\"", "\"c\""])
  |> pears.format_error()
  |> should.equal(
    "position 0: expected \"a\", \"b\" or \"c\", found end of input",
  )

  UnexpectedToken(0, [], "x")
  |> pears.format_error()
  |> should.equal("position 0: unexpected \"x\"")
}

pub fn line_column_test() {
  chars.line_column("ab\ncd", 0) |> should.equal(#(1, 1))
  chars.line_column("ab\ncd", 2) |> should.equal(#(1, 3))
  chars.line_column("ab\ncd", 4) |> should.equal(#(2, 2))
  chars.line_column("a\r\nb", 2) |> should.equal(#(2, 1))
}

pub fn chars_format_error_test() {
  UnexpectedToken(4, ["\"c\""], "d")
  |> chars.format_error("ab\ncd")
  |> should.equal("line 2, column 2: expected \"c\", found \"d\"")
}

pub fn many0_keeps_recovered_error_test() {
  left(many0(just("a")), just("b"))
  |> should_fail_with("aac", UnexpectedToken(2, ["\"a\"", "\"b\""], "c"))
}

pub fn maybe_keeps_recovered_error_test() {
  pair(maybe(just("-")), just("1"))
  |> should_fail_with("x", UnexpectedToken(0, ["\"-\"", "\"1\""], "x"))
}

pub fn sep_by0_keeps_recovered_error_test() {
  sep_by0(just("a"), just(","))
  |> between(just("["), just("]"))
  |> should_fail_with("[a a]", UnexpectedToken(2, ["\",\"", "\"]\""], " "))
}

pub fn recovered_error_further_than_failure_wins_test() {
  sep_by0(chars.string("ab"), just(","))
  |> between(just("["), just("]"))
  |> should_fail_with("[ab,ax]", UnexpectedToken(5, ["\"ab\""], "x"))
}

pub fn stale_recovered_error_is_dropped_test() {
  left(many0(just("a")), just("b"))
  |> left(just("c"))
  |> should_fail_with("aabx", UnexpectedToken(3, ["\"c\""], "x"))
}

pub fn hidden_test() {
  left(hidden(many0(just(" "))), just("a"))
  |> should_fail_with(" b", UnexpectedToken(1, ["\"a\""], "b"))

  hidden(just("a"))
  |> should_fail_with("b", UnexpectedToken(0, [], "b"))

  left(chars.whitespace0(), just("a"))
  |> should_fail_with("  b", UnexpectedToken(2, ["\"a\""], "b"))
}

pub fn labelled_relabels_recovered_error_test() {
  left(labelled(maybe(just("-")), "sign"), just("1"))
  |> should_fail_with("x", UnexpectedToken(0, ["sign", "\"1\""], "x"))
}

pub fn successful_parse_keeps_recovered_error_test() {
  let assert Ok(parsed) = pears.parse_string("aab", many0(just("a")))
  parsed.furthest_error
  |> should.equal(Some(UnexpectedToken(2, ["\"a\""], "b")))
}
