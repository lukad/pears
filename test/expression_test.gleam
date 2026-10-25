import gleam/int
import gleeunit/should
import helpers.{should_fail_with, should_parse}
import pears.{type Parser, UnexpectedEndOfInput}
import pears/chars.{type Char}
import pears/combinators.{
  alt, between, chainl1, chainr1, eof, just, lazy, left, to,
}

fn power(base: Int, exponent: Int) -> Int {
  case exponent {
    0 -> 1
    _ -> base * power(base, exponent - 1)
  }
}

// expression = term (("+" | "-") term)*
// term       = factor (("*" | "/") factor)*
// factor     = atom ("^" factor)?
// atom       = number | "(" expression ")"
fn expression() -> Parser(Char, Int) {
  let add = alt(to(just("+"), int.add), to(just("-"), int.subtract))
  let multiply =
    alt(to(just("*"), int.multiply), to(just("/"), fn(a, b) { a / b }))
  let atom =
    alt(chars.number(), between(lazy(expression), just("("), just(")")))

  let factor = chainr1(atom, to(just("^"), power))
  let term = chainl1(factor, multiply)
  chainl1(term, add)
}

fn parser() -> Parser(Char, Int) {
  left(expression(), eof())
}

pub fn chainl1_test() {
  let minus = to(just("-"), int.subtract)
  chainl1(chars.number(), minus)
  |> should_parse("7", 7)
  |> should_parse("10-2-3", 5)
}

pub fn chainr1_test() {
  let minus = to(just("-"), int.subtract)
  chainr1(chars.number(), minus)
  |> should_parse("7", 7)
  |> should_parse("10-2-3", 11)
  |> should_parse("10-2-3-4", 7)
}

pub fn precedence_test() {
  parser()
  |> should_parse("1+2*3", 7)
  |> should_parse("2*(3+4)-5", 9)
  |> should_parse("8/2/2", 2)
  |> should_parse("2^3^2", 512)
  |> should_parse("2*3^2", 18)
}

pub fn missing_operand_test() {
  parser()
  |> should_fail_with("1+", UnexpectedEndOfInput(2, ["digit", "\"(\""]))

  pears.parse_string_all("1+2*", expression())
  |> should.equal(Error(UnexpectedEndOfInput(4, ["digit", "\"(\""])))
}
