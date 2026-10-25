import gleam/list
import gleam/option.{None, Some}
import gleam/string
import helpers.{should_not_parse, should_parse}
import pears/chars
import pears/combinators.{
  between, just, left, many0, many1, maybe, not_followed_by, one_of, pair, peek,
  recognize, right, sep_by0, seq, succeed, then,
}

pub fn pair_test() {
  pair(just("a"), just("b"))
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
  many0(just("a"))
  |> should_parse("aaa", ["a", "a", "a"])
  |> should_parse("aaab", ["a", "a", "a"])
  |> should_parse("b", [])
}

pub fn many_long_input_test() {
  let n = 100_000
  many0(just("a"))
  |> should_parse(string.repeat("a", n), list.repeat("a", n))

  many1(just("a"))
  |> should_parse(string.repeat("a", n), list.repeat("a", n))

  sep_by0(just("a"), just(","))
  |> should_parse(list.repeat("a", n) |> string.join(","), list.repeat("a", n))
}

pub fn many_stops_on_empty_match_test() {
  many0(maybe(just("a")))
  |> should_parse("aab", [Some("a"), Some("a")])
  |> should_parse("b", [])

  many0(many0(just("a")))
  |> should_parse("aab", [["a", "a"]])
  |> should_parse("b", [])

  many1(maybe(just("a")))
  |> should_parse("b", [None])
}

pub fn many1_test() {
  many1(just("a"))
  |> should_parse("aaa", ["a", "a", "a"])
  |> should_parse("aaab", ["a", "a", "a"])
  |> should_not_parse("b")
}

pub fn between_test() {
  between(just("a"), just("("), just(")"))
  |> should_parse("(a)", "a")
  |> should_not_parse("(b)")

  between(many1(just("a")), just("("), just(")"))
  |> between(just("["), just("]"))
  |> should_parse("[(a)]", ["a"])
}

pub fn seq_test() {
  seq([just("a"), just("b"), just("c")])
  |> should_parse("abc", ["a", "b", "c"])
  |> should_not_parse("ab")
}

pub fn recognize_test() {
  just("x")
  |> right(recognize(pair(just("a"), just("b"))))
  |> should_parse("xabc", ["a", "b"])
  |> should_not_parse("xac")
}

pub fn string_test() {
  just("x")
  |> right(chars.string("ab"))
  |> right(just("c"))
  |> should_parse("xabc", "c")
  |> should_not_parse("xab")
  |> should_not_parse("xac")
}

pub fn succeed_test() {
  left(succeed(1), just("a"))
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
  pair(peek(just("a")), many0(just("a")))
  |> should_parse("aa", #("a", ["a", "a"]))
}

pub fn not_followed_by_test() {
  left(chars.string("let"), not_followed_by(one_of(["x", "y"])))
  |> should_parse("let", "let")
  |> should_parse("let z", "let")
  |> should_not_parse("letx")
}
