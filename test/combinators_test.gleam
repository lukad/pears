import gleam/string
import gleeunit/should
import pears.{type ParseResult, type Parser, ParseError, Parsed}
import pears/chars.{type Char}
import pears/combinators.{between, just, many0, many1, one_of, pair, seq}

fn parse(parser: Parser(Char, a), input: String) -> ParseResult(Char, a) {
  input
  |> string.to_graphemes()
  |> parser()
}

pub fn pair_test() {
  pair(just("a"), just("b"))
  |> parse("ab")
  |> should.equal(Ok(Parsed(input: [], value: #("a", "b"))))

  pair(just("a"), just("b"))
  |> parse("abc")
  |> should.equal(Ok(Parsed(input: ["c"], value: #("a", "b"))))

  pair(just("a"), just("b"))
  |> parse("ac")
  |> should.equal(Error(ParseError(["c"], ["\"b\""])))
}

pub fn one_of_test() {
  one_of(["a", "b"])
  |> parse("ab")
  |> should.equal(Ok(Parsed(["b"], "a")))

  one_of(["a", "b"])
  |> parse("bc")
  |> should.equal(Ok(Parsed(["c"], "b")))

  one_of(["a", "b"])
  |> parse("cd")
  |> should.equal(Error(ParseError(["c", "d"], ["satisfying"])))
}

pub fn many_test() {
  many0(just("a"))
  |> parse("aaa")
  |> should.equal(Ok(Parsed([], ["a", "a", "a"])))

  many0(just("a"))
  |> parse("aaab")
  |> should.equal(Ok(Parsed(["b"], ["a", "a", "a"])))

  many0(just("a"))
  |> parse("b")
  |> should.equal(Ok(Parsed(["b"], [])))
}

pub fn many1_test() {
  many1(just("a"))
  |> parse("aaa")
  |> should.equal(Ok(Parsed([], ["a", "a", "a"])))

  many1(just("a"))
  |> parse("aaab")
  |> should.equal(Ok(Parsed(["b"], ["a", "a", "a"])))

  many1(just("a"))
  |> parse("b")
  |> should.equal(Error(ParseError(["b"], ["\"a\""])))
}

// pub fn number_test() {
//   number()
//   |> parse("123")
//   |> should.equal(Ok(Parsed([], 123)))

//   number()
//   |> parse("123a")
//   |> should.equal(Ok(Parsed(["a"], 123)))

//   number()
//   |> parse("a")
//   |> should.equal(Error(ParseError(["a"], ["satisfying"])))
// }

pub fn between_test() {
  between(many1(just("a")), just("("), just(")"))
  |> parse("(aaa)")
  |> should.equal(Ok(Parsed([], ["a", "a", "a"])))

  between(just("a"), just("("), just(")"))
  |> parse("(b)")
  |> should.equal(Error(ParseError(["b", ")"], ["\"a\""])))
}

pub fn seq_test() {
  seq([just("a"), just("b"), just("c")])
  |> parse("abc")
  |> should.equal(Ok(Parsed([], ["a", "b", "c"])))

  seq([just("a"), just("b"), just("c")])
  |> parse("ab")
  |> should.equal(Error(ParseError([], ["\"c\""])))
}
