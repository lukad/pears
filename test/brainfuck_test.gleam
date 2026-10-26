import gleam/list
import helpers.{should_parse}
import pears.{type Parser}
import pears/chars.{type Char}
import pears/combinators.{
  between, eof, lazy, many0, many1, map, none_of, or, replace, skip_then,
  then_skip, token,
}

pub type Program =
  List(Instruction)

pub type Instruction {
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
  let padded = fn(p) { skip_then(comment(), p) }
  let add =
    or(token("+"), token("-"))
    |> many1()
    |> map(fn(x) { Add(count(x, "+") - count(x, "-")) })

  let move =
    or(token(">"), token("<"))
    |> many1()
    |> map(fn(x) { Mov(count(x, ">") - count(x, "<")) })

  let read = replace(token(","), Read)
  let write = replace(token("."), Write)

  let loop =
    lazy(instructions_parser)
    |> between(token("["), token("]"))
    |> map(Loop)

  add
  |> or(move)
  |> or(read)
  |> or(write)
  |> or(loop)
  |> padded()
  |> many0()
}

fn bf_parser() -> Parser(Char, Program) {
  instructions_parser()
  |> then_skip(comment())
  |> then_skip(eof())
}

pub fn parse_simple_instructions_test() {
  bf_parser()
  |> should_parse("+", [Add(1)])
  |> should_parse("-", [Add(-1)])
  |> should_parse(">", [Mov(1)])
  |> should_parse("<", [Mov(-1)])
  |> should_parse(",", [Read])
  |> should_parse(".", [Write])
}

pub fn parse_multiple_instructions_test() {
  bf_parser()
  |> should_parse("<><+++->><>>,.", [Mov(-1), Add(2), Mov(3), Read, Write])
}

pub fn parse_loops_test() {
  bf_parser()
  |> should_parse("[]", [Loop([])])
  |> should_parse("[+]", [Loop([Add(1)])])
  |> should_parse("[+[-]]", [Loop([Add(1), Loop([Add(-1)])])])
}

pub fn parse_hello_world_test() {
  bf_parser()
  |> should_parse(
    "+[-->-[>>+>-----<<]<--<---]>-.>>>+.>>..+++[.>]<<<<.+++.------.<<-.>>>>+.",
    [
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
    ],
  )
}
