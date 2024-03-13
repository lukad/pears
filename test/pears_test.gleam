import gleeunit
import gleeunit/should
import pears.{ParseError, Parsed}

pub fn main() {
  gleeunit.main()
}

pub fn hello_world_test() {
  pears.string("hello, world")
  |> pears.parse("hello, world")
  |> should.equal(Ok(Parsed(input: [], value: "hello, world")))

  pears.string("abc")
  |> pears.parse("abcd")
  |> should.equal(Ok(Parsed(input: ["d"], value: "abc")))

  pears.item(1)([1, 2, 3])
  |> should.equal(Ok(Parsed(input: [2, 3], value: 1)))
}

pub fn pair_test() {
  pears.pair(pears.string("a"), pears.string("b"))
  |> pears.parse("ab")
  |> should.equal(Ok(Parsed(input: [], value: #("a", "b"))))

  pears.pair(pears.string("a"), pears.string("b"))
  |> pears.parse("abc")
  |> should.equal(Ok(Parsed(input: ["c"], value: #("a", "b"))))

  pears.pair(pears.string("a"), pears.string("b"))
  |> pears.parse("ac")
  |> should.equal(Error(ParseError(["c"], ["b"])))
}

pub fn one_of_test() {
  pears.one_of(["a", "b"])
  |> pears.parse("ab")
  |> should.equal(Ok(Parsed(["b"], "a")))

  pears.one_of(["a", "b"])
  |> pears.parse("bc")
  |> should.equal(Ok(Parsed(["c"], "b")))

  pears.one_of(["a", "b"])
  |> pears.parse("cd")
  |> should.equal(Error(ParseError(["c", "d"], ["satisfying"])))
}

pub fn many_test() {
  pears.many0(pears.string("a"))
  |> pears.parse("aaa")
  |> should.equal(Ok(Parsed([], ["a", "a", "a"])))

  pears.many0(pears.string("a"))
  |> pears.parse("aaab")
  |> should.equal(Ok(Parsed(["b"], ["a", "a", "a"])))

  pears.many0(pears.string("a"))
  |> pears.parse("b")
  |> should.equal(Ok(Parsed(["b"], [])))
}

pub fn many1_test() {
  pears.many1(pears.string("a"))
  |> pears.parse("aaa")
  |> should.equal(Ok(Parsed([], ["a", "a", "a"])))

  pears.many1(pears.string("a"))
  |> pears.parse("aaab")
  |> should.equal(Ok(Parsed(["b"], ["a", "a", "a"])))

  pears.many1(pears.string("a"))
  |> pears.parse("b")
  |> should.equal(Error(ParseError(["b"], ["a"])))
}

pub fn number_test() {
  pears.number()
  |> pears.parse("123")
  |> should.equal(Ok(Parsed([], 123)))

  pears.number()
  |> pears.parse("123a")
  |> should.equal(Ok(Parsed(["a"], 123)))

  pears.number()
  |> pears.parse("a")
  |> should.equal(Error(ParseError(["a"], ["satisfying"])))
}

pub fn between_test() {
  pears.between(
    pears.string("("),
    pears.string(")"),
    pears.many1(pears.char("a")),
  )
  |> pears.parse("(aaa)")
  |> should.equal(Ok(Parsed([], ["a", "a", "a"])))

  pears.between(pears.string("("), pears.string(")"), pears.string("a"))
  |> pears.parse("(b)")
  |> should.equal(Error(ParseError(["b", ")"], ["a"])))
}

pub fn seq_test() {
  pears.seq([pears.char("a"), pears.char("b"), pears.char("c")])
  |> pears.parse("abc")
  |> should.equal(Ok(Parsed([], ["a", "b", "c"])))

  pears.seq([pears.char("a"), pears.char("b"), pears.char("c")])
  |> pears.parse("ab")
  |> should.equal(Error(ParseError([], ["\"c\""])))
}
