import gleeunit/should
import pears.{UnexpectedToken}
import pears/combinators.{just, many0, seq}
import pears/input

pub fn parse_string_all_test() {
  pears.parse_string_all("ab", seq([just("a"), just("b")]))
  |> should.equal(Ok(["a", "b"]))

  pears.parse_string_all("abc", seq([just("a"), just("b")]))
  |> should.equal(Error(UnexpectedToken(2, ["end of input"], "c")))

  pears.parse_string_all("aab", many0(just("a")))
  |> should.equal(Error(UnexpectedToken(2, ["\"a\"", "end of input"], "b")))
}

pub fn parse_all_test() {
  pears.parse_all([1, 1], many0(just(1)))
  |> should.equal(Ok([1, 1]))

  pears.parse_all([1, 2], many0(just(1)))
  |> should.equal(Error(UnexpectedToken(1, ["1", "end of input"], 2)))
}

pub fn input_test() {
  let in = input.new(["a", "b", "c"])
  input.position(in) |> should.equal(0)

  let in = input.next_n(in, 2)
  input.position(in) |> should.equal(2)
  input.tokens(in) |> should.equal(["c"])
  input.at_end(in) |> should.be_false()
  input.at_end(input.next(in)) |> should.be_true()
}
