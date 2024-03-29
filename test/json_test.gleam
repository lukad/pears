import gleam/float
import gleam/int
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pears.{type Parser}
import pears/chars.{type Char, digit, string}
import pears/combinators.{
  alt, between, choice, eof, just, lazy, left, many0, map, maybe, none_of,
  one_of, pair, recognize, right, sep_by0, seq, to,
}
import gleam/dict.{type Dict}
import helpers.{should_parse}

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
    |> map(string.concat)

  let frac =
    just(".")
    |> right(digits1)
    |> map(string.concat)

  let exp =
    alt(just("e"), just("E"))
    |> pair(maybe(one_of(["+", "-"])))
    |> pair(digits1)
    |> recognize()
    |> map(string.concat)

  let num =
    maybe(just("-"))
    |> pair(whole)
    |> pair(maybe(frac))
    |> pair(maybe(exp))
    |> map(fn(p) {
      let #(#(#(neg, whole), fraction), ex) = p
      let str =
        option.unwrap(neg, "")
        <> whole
        <> "."
        <> option.unwrap(fraction, "0")
        <> option.unwrap(ex, "")
      str
      |> float.parse()
      |> result.unwrap(case neg {
        Some(_) -> -1.7976931348623158e308
        None -> 1.7976931348623158e308
      })
    })
    |> map(Num)

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
    none_of(["\"", "\\"])
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

pub fn parse_numbers_test() {
  json_parser()
  |> should_parse("4.2", Num(4.2))
  |> should_parse("42", Num(42.0))
  |> should_parse("0", Num(0.0))
  |> should_parse("-0", Num(-0.0))
  |> should_parse("1e10", Num(1.0e10))
}

pub fn parse_large_floats() {
  // floats which are too large to be represented should be parsed as the max or min representable float
  json_parser()
  |> should_parse("1e1000", Num(1.7976931348623158e308))
  |> should_parse("-1e1000", Num(-1.7976931348623158e308))
}

pub fn parse_booleans_test() {
  json_parser()
  |> should_parse("true", Boolean(True))
  |> should_parse("false", Boolean(False))
}

pub fn parse_null_test() {
  json_parser()
  |> should_parse("null", Null)
}

pub fn parse_strings_test() {
  json_parser()
  |> should_parse("\"hello\"", Str("hello"))
  |> should_parse("\"hello\\nworld\"", Str("hello\nworld"))
  |> should_parse("\"\\u0048\\u0065\\u006c\\u006c\\u006f\"", Str("Hello"))
  |> should_parse("\"\\\"\"", Str("\""))
}

pub fn parse_arrays_test() {
  json_parser()
  |> should_parse("[]", Array([]))
  |> should_parse("[1, 2, 3]", Array([Num(1.0), Num(2.0), Num(3.0)]))
  |> should_parse(
    "[true, false, null]",
    Array([Boolean(True), Boolean(False), Null]),
  )
  |> should_parse("[\"hello\", \"world\"]", Array([Str("hello"), Str("world")]))
}

pub fn parse_objects_test() {
  json_parser()
  |> should_parse("{}", Obj(dict.new()))
  |> should_parse(
    "{\"a\": 1, \"b\": 2}",
    Obj(dict.from_list([#("a", Num(1.0)), #("b", Num(2.0))])),
  )
  |> should_parse(
    "{\"a\": true, \"b\": false, \"c\": null}",
    Obj(
      dict.from_list([
        #("a", Boolean(True)),
        #("b", Boolean(False)),
        #("c", Null),
      ]),
    ),
  )
  |> should_parse(
    "{\"a\": \"hello\", \"b\": \"world\"}",
    Obj(dict.from_list([#("a", Str("hello")), #("b", Str("world"))])),
  )
  |> should_parse(
    "{\"👋\": [1, 2, 3], \"b\": {\"c\": 4}}",
    Obj(
      dict.from_list([
        #("👋", Array([Num(1.0), Num(2.0), Num(3.0)])),
        #("b", Obj(dict.from_list([#("c", Num(4.0))]))),
      ]),
    ),
  )
}
