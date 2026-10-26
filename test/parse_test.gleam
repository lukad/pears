import gleeunit/should
import pears.{UnexpectedToken}
import pears/combinators.{many0, pair, seq, token}
import pears/input

pub fn parse_string_all_test() {
  pears.parse_string_all("ab", seq([token("a"), token("b")]))
  |> should.equal(Ok(["a", "b"]))

  pears.parse_string_all("abc", seq([token("a"), token("b")]))
  |> should.equal(Error(UnexpectedToken(2, ["end of input"], "c")))

  pears.parse_string_all("aab", many0(token("a")))
  |> should.equal(Error(UnexpectedToken(2, ["\"a\"", "end of input"], "b")))
}

pub fn parse_all_test() {
  pears.parse_all([1, 1], many0(token(1)))
  |> should.equal(Ok([1, 1]))

  pears.parse_all([1, 2], many0(token(1)))
  |> should.equal(Error(UnexpectedToken(1, ["1", "end of input"], 2)))
}

pub fn remaining_input_test() {
  let assert Ok(parsed) =
    pears.parse(["a", "b", "c"], pair(token("a"), token("b")))
  input.position(parsed.remaining) |> should.equal(2)
  input.tokens(parsed.remaining) |> should.equal(["c"])
  input.at_end(parsed.remaining) |> should.be_false()

  let assert Ok(parsed) = pears.parse(["a"], token("a"))
  input.at_end(parsed.remaining) |> should.be_true()
}
