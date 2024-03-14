import gleam/list
import gleam/string
import gleeunit/should
import pears.{type ParseResult, type Parser, Parsed}
import pears/chars.{type Char, char, string}
import pears/combinators.{
  alt, between, eof, lazy, left, many0, many1, map, none_of, right, to,
}

type Program =
  List(Instruction)

type Instruction {
  Add(Int)
  Mov(Int)
  Read
  Write
  Loop(Program)
}

fn count(xs: List(a), value: a) -> Int {
  list.fold(xs, 0, fn(acc, x) {
    case value == x {
      True -> acc + 1
      False -> acc
    }
  })
}

fn comment() -> Parser(Char, List(Char)) {
  many0(none_of(["+", "-", ">", "<", ",", ".", "[", "]"]))
}

fn instructions_parser() -> Parser(Char, Program) {
  let padded = fn(p) { right(comment(), p) }
  let add =
    alt(char("+"), char("-"))
    |> many1()
    |> map(fn(x) { Add(count(x, "+") - count(x, "-")) })

  let move =
    alt(char(">"), char("<"))
    |> many1()
    |> map(fn(x) { Mov(count(x, ">") - count(x, "<")) })

  let read = to(char(","), Read)
  let write = to(char("."), Write)

  let loop =
    lazy(instructions_parser)
    |> between(char("["), char("]"))
    |> map(Loop)

  add
  |> alt(move)
  |> alt(read)
  |> alt(write)
  |> alt(loop)
  |> padded()
  |> many0()
}

fn bf_parser() -> Parser(Char, Program) {
  instructions_parser()
  |> left(comment())
  |> left(eof())
}

fn parse(input: String) -> ParseResult(_, Program) {
  input
  |> string.to_graphemes()
  |> bf_parser()
}

pub fn parse_loops_test() {
  parse("[]")
  |> should.equal(Ok(Parsed([], [Loop([])])))
}

pub fn parse_simple_instructions_test() {
  parse("<><+++->><>>,.")
  |> should.equal(Ok(Parsed([], [Mov(-1), Add(2), Mov(3), Read, Write])))
}

pub fn parse_hello_world_test() {
  parse(
    "+[-->-[>>+>-----<<]<--<---]>-.>>>+.>>..+++[.>]<<<<.+++.------.<<-.>>>>+.",
  )
  |> should.equal(
    Ok(
      Parsed([], [
        Add(1),
        Loop([
          Add(-2),
          Mov(1),
          Add(-1),
          Loop([Mov(2), Add(1), Mov(1), Add(-5), Mov(-2)]),
          Mov(-1),
          Add(-2),
          Mov(-1),
          Add(-3),
        ]),
        Mov(1),
        Add(-1),
        Write,
        Mov(3),
        Add(1),
        Write,
        Mov(2),
        Write,
        Write,
        Add(3),
        Loop([Write, Mov(1)]),
        Mov(-4),
        Write,
        Add(3),
        Write,
        Add(-6),
        Write,
        Mov(-2),
        Add(-1),
        Write,
        Mov(4),
        Add(1),
        Write,
      ]),
    ),
  )
}
