import gleam/float
import gleam/int
import gleam/string
import gleeunit/should
import pears.{type ParseResult, type Parser, Parsed}
import pears/chars.{type Char, digit, string}
import pears/combinators.{
  alt, between, choice, eof, just, lazy, left, many0, map, maybe, none_of,
  one_of, pair, recognize, right, sep_by0, seq, to,
}
import gleam/dict.{type Dict}

pub type Json {
  Str(String)
  Num(Float)
  Obj(Dict(String, Json))
  Array(List(Json))
  Boolean(Bool)
  Null
}

fn whitespace0() -> Parser(Char, List(Char)) {
  one_of([" ", "\n", "\r", "\t"])
  |> many0()
}

fn value_parser() -> Parser(Char, Json) {
  let padded = fn(parser: Parser(_, a)) { left(parser, whitespace0()) }
  let symbol = fn(s: String) { padded(string(s)) }

  let digits0 = many0(digit())

  let digits1 = many0(digit())

  let whole =
    alt(
      to(just("0"), ["0"]),
      recognize(pair(
        one_of(["1", "2", "3", "4", "5", "6", "7", "8", "9"]),
        digits0,
      )),
    )

  let frac =
    just(".")
    |> right(digits1)

  let exp =
    alt(just("e"), just("E"))
    |> pair(maybe(one_of(["+", "-"])))
    |> pair(digits1)

  let num =
    maybe(just("-"))
    |> pair(whole)
    |> pair(maybe(frac))
    |> pair(maybe(exp))
    |> recognize()
    |> map(fn(chars) {
      let str = string.concat(chars)
      let number = float.parse(str)

      case number {
        Ok(num) -> Num(num)
        Error(_) -> {
          let assert Ok(number) = int.parse(str)
          Num(int.to_float(number))
        }
      }
    })

  let bool =
    alt(to(string("true"), Boolean(True)), to(string("false"), Boolean(False)))

  let null = to(string("null"), Null)

  let hex_digit =
    one_of([
      "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e",
      "f", "A", "B", "C", "D", "E", "F",
    ])

  let unicode_escape_digits =
    recognize(seq([hex_digit, hex_digit, hex_digit, hex_digit]))

  let escape =
    just("\\")
    |> right(
      choice([
        just("\\"),
        just("/"),
        just("\""),
        to(just("b"), "\u{0008}"),
        to(just("f"), "\u{000C}"),
        to(just("n"), "\n"),
        to(just("r"), "\r"),
        to(just("t"), "\t"),
        map(right(just("u"), unicode_escape_digits), fn(value) {
          let assert Ok(number) = int.base_parse(string.concat(value), 16)
          let assert Ok(codepoint) = string.utf_codepoint(number)
          string.from_utf_codepoints([codepoint])
        }),
      ]),
    )

  let str =
    none_of(["\""])
    |> alt(escape)
    |> many0()
    |> map(string.concat)
    |> between(just("\""), just("\""))

  let value = lazy(value_parser)

  let array =
    sep_by0(value, symbol(","))
    |> between(symbol("["), symbol("]"))
    |> map(Array)

  let key_value =
    str
    |> left(symbol(":"))
    |> pair(value)

  let key_values =
    key_value
    |> sep_by0(symbol(","))
    |> map(dict.from_list)

  let obj =
    key_values
    |> between(symbol("{"), symbol("}"))
    |> map(Obj)

  choice([num, bool, null, map(str, Str), array, obj])
  |> padded()
}

fn json_parser() -> Parser(Char, Json) {
  value_parser()
  |> between(whitespace0(), eof())
}

fn parse(input: String) -> ParseResult(Char, Json) {
  input
  |> string.to_graphemes()
  |> json_parser()
}

pub fn parse_numbers_test() {
  parse("42.0")
  |> should.equal(Ok(Parsed([], Num(42.0))))

  parse("2.3")
  |> should.equal(Ok(Parsed([], Num(2.3))))
}

pub fn parse_booleans_test() {
  parse("true")
  |> should.equal(Ok(Parsed([], Boolean(True))))

  parse("false")
  |> should.equal(Ok(Parsed([], Boolean(False))))

  parse("null")
  |> should.equal(Ok(Parsed([], Null)))
}

pub fn parse_strings_test() {
  parse("\"hello\"")
  |> should.equal(Ok(Parsed([], Str("hello"))))

  parse("\"hello world\"")
  |> should.equal(Ok(Parsed([], Str("hello world"))))
}

pub fn parse_arrays_test() {
  parse("[]")
  |> should.equal(Ok(Parsed([], Array([]))))

  parse("[ 1, 2, 3 ]")
  |> should.equal(Ok(Parsed([], Array([Num(1.0), Num(2.0), Num(3.0)]))))

  parse("[true, false, null]")
  |> should.equal(Ok(Parsed([], Array([Boolean(True), Boolean(False), Null]))))

  parse("[\"hello\", \"world\"]")
  |> should.equal(Ok(Parsed([], Array([Str("hello"), Str("world")]))))
}

pub fn parse_objects_test() {
  parse("{}")
  |> should.equal(Ok(Parsed([], Obj(dict.new()))))

  parse("{\"a\": 1, \"b\": 2}")
  |> should.equal(
    Ok(Parsed([], Obj(dict.from_list([#("a", Num(1.0)), #("b", Num(2.0))])))),
  )

  parse("{\"a\": true, \"b\": false, \"c\": null}")
  |> should.equal(
    Ok(Parsed(
      [],
      Obj(
        dict.from_list([
          #("a", Boolean(True)),
          #("b", Boolean(False)),
          #("c", Null),
        ]),
      ),
    )),
  )

  parse("{\"a\": \"hello\", \"b\": \"world\"}")
  |> should.equal(
    Ok(Parsed(
      [],
      Obj(dict.from_list([#("a", Str("hello")), #("b", Str("world"))])),
    )),
  )

  parse("{\"👋\": [1, 2, 3], \"b\": {\"c\": 4}}")
  |> should.equal(
    Ok(Parsed(
      [],
      Obj(
        dict.from_list([
          #("👋", Array([Num(1.0), Num(2.0), Num(3.0)])),
          #("b", Obj(dict.from_list([#("c", Num(4.0))]))),
        ]),
      ),
    )),
  )
}
