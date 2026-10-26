import gleam/list
import gleam/option.{None, Some}
import gleam/string
import helpers.{should_not_parse, should_parse}
import pears.{Span}
import pears/chars
import pears/combinators.{
  any, at_least, at_most, between, exactly, many0, many1, many_till,
  not_followed_by, one_of, optional, pair, peek, recognize, sep_by0, sep_end_by0,
  sep_end_by1, seq, skip_then, succeed, then, then_skip, token, with_span,
}

pub fn pair_test() {
  pair(token("a"), token("b"))
  |> should_parse("ab", #("a", "b"))
  |> should_parse("abc", #("a", "b"))
  |> should_not_parse("ac")
}

pub fn one_of_test() {
  one_of(["a", "b"])
  |> should_parse("ab", "a")
  |> should_parse("bc", "b")
  |> should_not_parse("d")
}

pub fn many_test() {
  many0(token("a"))
  |> should_parse("aaa", ["a", "a", "a"])
  |> should_parse("aaab", ["a", "a", "a"])
  |> should_parse("b", [])
}

pub fn many_long_input_test() {
  let n = 100_000
  many0(token("a"))
  |> should_parse(string.repeat("a", n), list.repeat("a", n))

  many1(token("a"))
  |> should_parse(string.repeat("a", n), list.repeat("a", n))

  sep_by0(token("a"), token(","))
  |> should_parse(list.repeat("a", n) |> string.join(","), list.repeat("a", n))
}

pub fn many_stops_on_empty_match_test() {
  many0(optional(token("a")))
  |> should_parse("aab", [Some("a"), Some("a")])
  |> should_parse("b", [])

  many0(many0(token("a")))
  |> should_parse("aab", [["a", "a"]])
  |> should_parse("b", [])

  many1(optional(token("a")))
  |> should_parse("b", [None])
}

pub fn many1_test() {
  many1(token("a"))
  |> should_parse("aaa", ["a", "a", "a"])
  |> should_parse("aaab", ["a", "a", "a"])
  |> should_not_parse("b")
}

pub fn between_test() {
  between(token("a"), token("("), token(")"))
  |> should_parse("(a)", "a")
  |> should_not_parse("(b)")

  between(many1(token("a")), token("("), token(")"))
  |> between(token("["), token("]"))
  |> should_parse("[(a)]", ["a"])
}

pub fn seq_test() {
  seq([token("a"), token("b"), token("c")])
  |> should_parse("abc", ["a", "b", "c"])
  |> should_not_parse("ab")
}

pub fn recognize_test() {
  token("x")
  |> skip_then(recognize(pair(token("a"), token("b"))))
  |> should_parse("xabc", ["a", "b"])
  |> should_not_parse("xac")
}

pub fn string_test() {
  token("x")
  |> skip_then(chars.string("ab"))
  |> skip_then(token("c"))
  |> should_parse("xabc", "c")
  |> should_not_parse("xab")
  |> should_not_parse("xac")
}

pub fn succeed_test() {
  then_skip(succeed(1), token("a"))
  |> should_parse("a", 1)
}

pub fn then_test() {
  let digits_then_letter = {
    use digits <- then(many1(chars.digit()))
    use letter <- then(one_of(["a", "b"]))
    succeed(#(digits, letter))
  }

  digits_then_letter
  |> should_parse("12b", #(["1", "2"], "b"))
  |> should_not_parse("12c")
  |> should_not_parse("b")
}

pub fn peek_test() {
  pair(peek(token("a")), many0(token("a")))
  |> should_parse("aa", #("a", ["a", "a"]))
}

pub fn not_followed_by_test() {
  then_skip(chars.string("let"), not_followed_by(one_of(["x", "y"])))
  |> should_parse("let", "let")
  |> should_parse("let z", "let")
  |> should_not_parse("letx")
}

pub fn exactly_test() {
  exactly(token("a"), 2)
  |> should_parse("aaa", ["a", "a"])
  |> should_not_parse("a")

  exactly(optional(token("a")), 3)
  |> should_parse("a", [Some("a"), None, None])
}

pub fn at_least_test() {
  at_least(token("a"), 2)
  |> should_parse("aa", ["a", "a"])
  |> should_parse("aaaa", ["a", "a", "a", "a"])
  |> should_not_parse("a")

  at_least(optional(token("a")), 0)
  |> should_parse("", [])
}

pub fn at_most_test() {
  at_most(token("a"), 2)
  |> should_parse("", [])
  |> should_parse("aaa", ["a", "a"])

  at_most(optional(token("a")), 3)
  |> should_parse("", [])
}

pub fn many_till_test() {
  many_till(any(), token(";"))
  |> should_parse(";", [])
  |> should_parse("ab;c", ["a", "b"])
  |> should_not_parse("ab")

  let n = 100_000
  many_till(token("a"), token(";"))
  |> should_parse(string.repeat("a", n) <> ";", list.repeat("a", n))
}

pub fn sep_end_by_test() {
  sep_end_by0(token("a"), token(","))
  |> should_parse("", [])
  |> should_parse(",", [])
  |> should_parse("a,a", ["a", "a"])
  |> should_parse("a,a,", ["a", "a"])

  sep_end_by1(token("a"), token(","))
  |> should_parse("a,", ["a"])
  |> should_not_parse(",")
}

pub fn with_span_test() {
  with_span(many0(token("a")))
  |> should_parse("aab", #(["a", "a"], Span(0, 2)))
  |> should_parse("b", #([], Span(0, 0)))

  skip_then(token("x"), with_span(chars.string("ab")))
  |> should_parse("xab", #("ab", Span(1, 3)))
}
