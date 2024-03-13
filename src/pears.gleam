import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result.{try}
import gleam/string
import pears/input.{type Char, type Input}

pub type Parsed(i, a) {
  Parsed(input: Input(i), value: a)
}

pub type ParseError(i) {
  ParseError(input: Input(i), expected: List(String))
}

pub type ParseResult(i, a) =
  Result(Parsed(i, a), ParseError(i))

pub type Parser(i, a) =
  fn(Input(i)) -> ParseResult(i, a)

pub fn parse(parser: Parser(Char, a), input: String) -> ParseResult(Char, a) {
  parser(string.to_graphemes(input))
}

fn ok(input: Input(i), value: a) -> ParseResult(i, a) {
  Ok(Parsed(input, value))
}

/// Maps the result of a parser to a new value using a mapper function
pub fn map(p: Parser(i, a), fun: fn(a) -> b) -> Parser(i, b) {
  fn(input: Input(i)) {
    p(input)
    |> result.map(fn(parsed) {
      Parsed(input: parsed.input, value: fun(parsed.value))
    })
  }
}

/// Maps the result of a parser to a constant value
pub fn to(parser: Parser(i, a), value: b) -> Parser(i, b) {
  map(parser, fn(_) { value })
}

pub fn alt(parser_1: Parser(i, a), parser_2: Parser(i, a)) -> Parser(i, a) {
  fn(input: Input(i)) {
    case parser_1(input) {
      Ok(result) -> Ok(result)
      Error(_) -> parser_2(input)
    }
  }
}

pub fn any() -> Parser(i, i) {
  fn(in: Input(i)) {
    case input.get(in) {
      None -> Error(ParseError(in, ["any"]))
      Some(#(value, next)) -> ok(next, value)
    }
  }
}

pub fn eof() -> Parser(i, Nil) {
  fn(input: Input(i)) {
    case input {
      [] -> ok(input, Nil)
      _ -> Error(ParseError(input, ["EOF"]))
    }
  }
}

pub type Predicate(i) =
  fn(i) -> Bool

pub fn satisfying(f: Predicate(i)) -> Parser(i, i) {
  fn(in: Input(i)) {
    case input.get(in) {
      None -> Error(ParseError(in, ["satisfying"]))
      Some(#(value, next)) ->
        case f(value) {
          True -> ok(next, value)
          False -> Error(ParseError(in, ["satisfying"]))
        }
    }
  }
}

pub fn then(parser_a: Parser(i, a), parser_b: Parser(i, b)) -> Parser(i, b) {
  fn(input: Input(i)) {
    case parser_a(input) {
      Ok(parsed) -> parser_b(parsed.input)
      Error(err) -> Error(err)
    }
  }
}

pub fn item(item: i) -> Parser(i, i) {
  fn(input: Input(i)) {
    case input {
      [head, ..next] if head == item -> ok(next, head)
      _ -> Error(ParseError(input, [string.inspect(item)]))
    }
  }
}

pub fn pair(
  parser_1 p1: Parser(i, a),
  parser_2 p2: Parser(i, b),
) -> Parser(i, #(a, b)) {
  fn(in: Input(i)) {
    use parsed_1 <- try(p1(in))
    use parsed_2 <- try(p2(parsed_1.input))
    ok(parsed_2.input, #(parsed_1.value, parsed_2.value))
  }
}

/// Applies the given parsers in sequence and returns a list of the results
///
pub fn seq(parsers: List(Parser(i, a))) -> Parser(i, List(a)) {
  fn(input: Input(i)) { do_sequence(parsers, input, []) }
}

fn do_sequence(
  parsers: List(Parser(i, a)),
  input: Input(i),
  acc: List(a),
) -> ParseResult(i, List(a)) {
  case parsers {
    [] -> ok(input, list.reverse(acc))
    [parser, ..rest] -> {
      use parsed <- try(parser(input))
      do_sequence(rest, parsed.input, [parsed.value, ..acc])
    }
  }
}

pub fn left(
  parser_1 p1: Parser(i, a),
  parser_2 p2: Parser(i, b),
) -> Parser(i, a) {
  fn(in: Input(i)) {
    use parsed_1 <- try(p1(in))
    use parsed_2 <- try(p2(parsed_1.input))
    ok(parsed_2.input, parsed_1.value)
  }
}

pub fn right(
  parser_1 p1: Parser(i, a),
  parser_2 p2: Parser(i, b),
) -> Parser(i, b) {
  fn(in: Input(i)) {
    use parsed_1 <- try(p1(in))
    use parsed_2 <- try(p2(parsed_1.input))
    ok(parsed_2.input, parsed_2.value)
  }
}

/// Parses zero or more occurrences of the given parser
pub fn many0(parser: Parser(i, a)) -> Parser(i, List(a)) {
  fn(in: Input(i)) {
    case parser(in) {
      Ok(parsed) -> {
        use next <- try(many0(parser)(parsed.input))
        ok(next.input, [parsed.value, ..next.value])
      }
      Error(_) -> ok(in, [])
    }
  }
}

/// Parses one or more occurrences of the given parser
pub fn many1(parser: Parser(i, a)) -> Parser(i, List(a)) {
  fn(in: Input(i)) {
    use parsed <- try(parser(in))
    use rest <- try(many0(parser)(parsed.input))
    ok(rest.input, [parsed.value, ..rest.value])
  }
}

/// Lazily evaluates the given parser allowing for recursive parsers
pub fn lazy(f: fn() -> Parser(i, a)) -> Parser(i, a) {
  fn(input) { f()(input) }
}

pub fn char(c: Char) -> Parser(Char, Char) {
  item(c)
}

pub fn string(str: String) -> Parser(Char, String) {
  fn(input: Input(Char)) {
    let s = string.to_graphemes(str)
    let length = list.length(s)
    case list.length(input) >= length {
      True -> {
        let candidate = list.take(input, length)
        case candidate == s {
          True -> ok(list.drop(input, length), str)
          False -> Error(ParseError(input, [str]))
        }
      }
      False -> Error(ParseError(input, [str]))
    }
  }
}

pub fn one_of(items: List(i)) -> Parser(i, i) {
  satisfying(fn(c) { list.contains(items, c) })
}

pub fn digit() -> Parser(Char, Char) {
  one_of(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])
}

pub fn number() -> Parser(Char, Int) {
  many1(digit())
  |> map(fn(digits) {
    list.fold(digits, 0, fn(acc, digit) {
      let assert Ok(digit) = int.parse(digit)
      acc * 10 + digit
    })
  })
}

pub fn between(
  open: Parser(i, a),
  close: Parser(i, b),
  parser: Parser(i, c),
) -> Parser(i, c) {
  open
  |> right(parser)
  |> left(close)
}

pub fn whitespace() -> Parser(Char, Char) {
  satisfying(fn(c) { string.trim(c) == "" })
}

pub fn whitespace0() -> Parser(Char, List(Char)) {
  many0(whitespace())
}

pub fn whitespace1() -> Parser(Char, List(Char)) {
  many1(whitespace())
}
