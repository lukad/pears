import pears/combinators.{between, just, many0, many1, one_of, pair, seq}
import helpers.{should_not_parse, should_parse}

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
