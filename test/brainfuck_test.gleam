import gleam/list
import gleeunit/should
import pears.{type ParseResult, type Parser, Parsed}
import pears/input.{type Char}

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

fn instructions_parser() -> Parser(Char, Program) {
  let add =
    pears.many1(pears.alt(pears.char("+"), pears.char("-")))
    |> pears.map(fn(x) { Add(count(x, "+") - count(x, "-")) })

  let move =
    pears.many1(pears.alt(pears.char(">"), pears.char("<")))
    |> pears.map(fn(x) { Mov(count(x, ">") - count(x, "<")) })

  let read =
    pears.char(",")
    |> pears.to(Read)

  let write =
    pears.char(".")
    |> pears.to(Write)

  let loop =
    pears.between(
      pears.char("["),
      pears.char("]"),
      pears.lazy(instructions_parser),
    )
    |> pears.map(Loop)

  add
  |> pears.alt(move)
  |> pears.alt(read)
  |> pears.alt(write)
  |> pears.alt(loop)
  |> pears.many0()
}

fn bf_parser() -> Parser(Char, Program) {
  pears.left(instructions_parser(), pears.eof())
}

fn parse(input: String) -> ParseResult(_, Program) {
  pears.parse(bf_parser(), input)
}

pub fn parser_test() {
  parse("[]")
  |> should.equal(Ok(Parsed([], [Loop([])])))

  parse("<+++->><>>,.[.]")
  |> should.equal(
    Ok(Parsed([], [Mov(-1), Add(2), Mov(3), Read, Write, Loop([Write])])),
  )

  parse("++++++++[>++++++++<-]>.")
  |> should.equal(
    Ok(
      Parsed([], [
        Add(8),
        Loop([Mov(1), Add(8), Mov(-1), Add(-1)]),
        Mov(1),
        Write,
      ]),
    ),
  )
}
