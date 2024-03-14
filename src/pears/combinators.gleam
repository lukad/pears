import gleam/list
import gleam/string
import gleam/option.{type Option, None, Some}
import gleam/result.{try}
import pears.{type ParseResult, type Parser, ParseError, Parsed, ok}
import pears/input.{type Input}

/// Maps the result of a parser to a new value using a mapper function.
pub fn map(p: Parser(i, a), fun: fn(a) -> b) -> Parser(i, b) {
  fn(input: Input(i)) {
    p(input)
    |> result.map(fn(parsed) {
      Parsed(input: parsed.input, value: fun(parsed.value))
    })
  }
}

/// Maps the result of a parser to a constant value.
pub fn to(parser: Parser(i, a), value: b) -> Parser(i, b) {
  map(parser, fn(_) { value })
}

/// Tries to apply the first parser, if it fails it applies the second parser.
pub fn alt(parser_1: Parser(i, a), parser_2: Parser(i, a)) -> Parser(i, a) {
  fn(input: Input(i)) {
    case parser_1(input) {
      Ok(result) -> Ok(result)
      Error(_) -> parser_2(input)
    }
  }
}

/// Consumes any single item from the input except for the end of file.
pub fn any() -> Parser(i, i) {
  fn(in: Input(i)) {
    case input.get(in) {
      None -> Error(ParseError(in, ["any"]))
      Some(#(value, next)) -> ok(next, value)
    }
  }
}

/// Consumes the end of the input and returns a Nil value. Fails if there is any input left.
pub fn eof() -> Parser(i, Nil) {
  fn(in: Input(i)) {
    case input.at_end(in) {
      True -> ok(in, Nil)
      False -> Error(ParseError(in, ["EOF"]))
    }
  }
}

/// A predicate function that returns a boolean value for a given input item of type `i`.
pub type Predicate(i) =
  fn(i) -> Bool

/// Consumes a single item from the input that satisfies the given predicate function.
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

/// Consumes a single item from the input that is equal to the given item.
pub fn just(item: i) -> Parser(i, i) {
  fn(input: Input(i)) {
    case input {
      [head, ..next] if head == item -> ok(next, head)
      _ -> Error(ParseError(input, [string.inspect(item)]))
    }
  }
}

// Applies both parsers and returns a tuple of the results
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

/// Applies the first parser and then the second parser, returning the result of the first parser.
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

/// Applies the first parser and then the second parser, returning the result of the second parser.
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

/// Applies the given parser zero or more times.
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

/// Applies the given parser one or more times.
pub fn many1(parser: Parser(i, a)) -> Parser(i, List(a)) {
  fn(in: Input(i)) {
    use parsed <- try(parser(in))
    use rest <- try(many0(parser)(parsed.input))
    ok(rest.input, [parsed.value, ..rest.value])
  }
}

/// Lazily applies the given parser allowing for recursive parsers.
///
/// ## Examples
///
/// Parsing a recursive list of chars:
///
/// ```gleam
/// pub type Tree(a) {
///   Leaf(a)
///   Node(List(Tree(a)))
/// }
///
/// fn tree_parser() -> Parser(Char, Tree(Int)) {
///   let tree = lazy(tree_parser)
///   let leaf = map(number(), Leaf)
///   let node =
///     tree
///     |> sep_by0(just(","))
///     |> between(just("["), just("]"))
///     |> map(Node)
///   alt(leaf, node)
/// }
/// ```
pub fn lazy(f: fn() -> Parser(i, a)) -> Parser(i, a) {
  fn(input) { f()(input) }
}

/// Consumes an item that is included in the given list.
pub fn one_of(items: List(i)) -> Parser(i, i) {
  satisfying(fn(c) { list.contains(items, c) })
}

/// Consumes an item that is not included in the given list.
pub fn none_of(items: List(i)) -> Parser(i, i) {
  satisfying(fn(c) { !list.contains(items, c) })
}

/// Applies the given parser between the open and close parsers, returning the result of the innner parser.
pub fn between(
  parser: Parser(i, a),
  open: Parser(i, b),
  close: Parser(i, c),
) -> Parser(i, a) {
  open
  |> right(parser)
  |> left(close)
}

/// Tries to apply the given parsers in order and returns the result of the first one that succeeds.
pub fn choice(parsers: List(Parser(i, a))) -> Parser(i, a) {
  fn(input: Input(i)) {
    case parsers {
      [] -> Error(ParseError(input, ["choice"]))
      [parser, ..rest] -> {
        case parser(input) {
          Ok(parsed) -> Ok(parsed)
          Error(_) -> choice(rest)(input)
        }
      }
    }
  }
}

/// Parses zero or more occurrences of the given parser separated by the given separator.
pub fn sep_by0(
  parser: Parser(i, a),
  separator: Parser(i, b),
) -> Parser(i, List(a)) {
  fn(in: Input(i)) {
    case parser(in) {
      Ok(parsed) -> {
        use rest <- try(many0(right(separator, parser))(parsed.input))
        ok(rest.input, [parsed.value, ..rest.value])
      }
      Error(_) -> ok(in, [])
    }
  }
}

/// Parses one or more occurrences of the given parser separated by the given separator.
pub fn sep_by1(
  parser: Parser(i, a),
  separator: Parser(i, b),
) -> Parser(i, List(a)) {
  fn(input: Input(i)) {
    use parsed <- try(parser(input))
    use rest <- try(many0(
      separator
      |> right(parser),
    )(parsed.input))
    ok(rest.input, [parsed.value, ..rest.value])
  }
}

/// Applies the given parser and wraps the result in an `Option`,
/// returning `None` if the parser fails instead of an error.
pub fn maybe(parser: Parser(i, a)) -> Parser(i, Option(a)) {
  fn(in: Input(i)) {
    case parser(in) {
      Ok(parsed) -> ok(parsed.input, Some(parsed.value))
      Error(_) -> ok(in, None)
    }
  }
}

/// Maps a parser that returns an `Option` to a parser that returns a value or a default value.
pub fn unwrap(parser: Parser(i, Option(a)), default: a) -> Parser(i, a) {
  parser
  |> map(fn(maybe_value) {
    case maybe_value {
      None -> default
      Some(value) -> value
    }
  })
}

/// Creates a parser that returns the consumed tokens instead of it's parsed value.
pub fn recognize(parser: Parser(i, a)) -> Parser(i, List(i)) {
  fn(in: Input(i)) {
    use parsed <- try(parser(in))
    let original_length = list.length(in)
    let parsed_length = list.length(parsed.input)
    let consumed = list.take(in, original_length - parsed_length)
    ok(parsed.input, consumed)
  }
}
