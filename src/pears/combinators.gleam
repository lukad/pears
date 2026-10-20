import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import pears.{
  type ParseError, type ParseResult, type Parsed, type Parser, Parsed,
  UnexpectedEndOfInput, UnexpectedToken, ok,
}
import pears/input.{type Input, Input}

fn error_at(in: Input(i), expected: List(String)) -> ParseError(i) {
  case input.get(in) {
    None -> UnexpectedEndOfInput(in.cursor, expected)
    Some(token) -> UnexpectedToken(in.cursor, expected, token)
  }
}

fn with_expected(
  error: ParseError(i),
  expected: List(String),
) -> ParseError(i) {
  case error {
    UnexpectedEndOfInput(position, _) ->
      UnexpectedEndOfInput(position, expected)
    UnexpectedToken(position, _, found) ->
      UnexpectedToken(position, expected, found)
  }
}

/// Keeps the error that got furthest, combining expectations at the same position.
fn merge_errors(a: ParseError(i), b: ParseError(i)) -> ParseError(i) {
  case int.compare(a.position, b.position) {
    order.Gt -> a
    order.Lt -> b
    order.Eq ->
      with_expected(b, list.unique(list.append(a.expected, b.expected)))
  }
}

fn merge_optional_errors(
  a: Option(ParseError(i)),
  b: Option(ParseError(i)),
) -> Option(ParseError(i)) {
  case a, b {
    None, _ -> b
    _, None -> a
    Some(a), Some(b) -> Some(merge_errors(a, b))
  }
}

/// Drops a recovered error before `cursor`, since any later error wins over it.
fn relevant(
  error: Option(ParseError(i)),
  cursor: Int,
) -> Option(ParseError(i)) {
  case error {
    Some(error) if error.position < cursor -> None
    _ -> error
  }
}

/// Adds a recovered error to a successful result. `parsed.furthest_error` is
/// never before the cursor, so only `error` needs checking.
fn recover(parsed: Parsed(i, a), error: Option(ParseError(i))) -> Parsed(i, a) {
  case error {
    None -> parsed
    Some(error) if error.position < parsed.input.cursor -> parsed
    Some(error) ->
      Parsed(
        ..parsed,
        furthest_error: merge_optional_errors(
          Some(error),
          parsed.furthest_error,
        ),
      )
  }
}

/// Like `result.try`, but carries over the recovered error of `result`.
fn continue(
  result: ParseResult(i, a),
  next: fn(Parsed(i, a)) -> ParseResult(i, b),
) -> ParseResult(i, b) {
  case result {
    Error(error) -> Error(error)
    Ok(Parsed(furthest_error: None, ..) as parsed) -> next(parsed)
    Ok(Parsed(furthest_error: Some(recovered), ..) as parsed) ->
      case next(parsed) {
        Ok(next_parsed) -> Ok(recover(next_parsed, Some(recovered)))
        Error(error) -> Error(merge_errors(recovered, error))
      }
  }
}

/// Maps the result of a parser to a new value using a mapper function.
pub fn map(p: Parser(i, a), fun: fn(a) -> b) -> Parser(i, b) {
  fn(input: Input(i)) {
    p(input)
    |> result.map(fn(parsed) {
      Parsed(
        input: parsed.input,
        value: fun(parsed.value),
        furthest_error: parsed.furthest_error,
      )
    })
  }
}

/// Maps the error of a parser to a new error using a mapper function.
pub fn map_error(
  p: Parser(i, a),
  fun: fn(ParseError(i)) -> ParseError(i),
) -> Parser(i, a) {
  fn(input: Input(i)) {
    p(input)
    |> result.map_error(fun)
  }
}

/// Reports `label` as expected when the parser fails without consuming input.
pub fn labelled(parser: Parser(i, a), label: String) -> Parser(i, a) {
  fn(in: Input(i)) {
    case parser(in) {
      Error(error) if error.position == in.cursor ->
        Error(with_expected(error, [label]))
      Ok(Parsed(furthest_error: Some(error), ..) as parsed)
        if error.position == in.cursor
      ->
        Ok(
          Parsed(..parsed, furthest_error: Some(with_expected(error, [label]))),
        )
      result -> result
    }
  }
}

/// Leaves the parser out of error messages, e.g. for optional whitespace.
pub fn hidden(parser: Parser(i, a)) -> Parser(i, a) {
  fn(in: Input(i)) {
    case parser(in) {
      Ok(parsed) -> Ok(Parsed(..parsed, furthest_error: None))
      Error(error) if error.position == in.cursor ->
        Error(with_expected(error, []))
      Error(error) -> Error(error)
    }
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
      Ok(_) as result -> result
      Error(error_1) ->
        case parser_2(input) {
          Ok(parsed) as result if error_1.position < parsed.input.cursor ->
            result
          Ok(parsed) -> Ok(recover(parsed, Some(error_1)))
          Error(error_2) -> Error(merge_errors(error_1, error_2))
        }
    }
  }
}

/// Consumes any single item from the input except for the end of file.
pub fn any() -> Parser(i, i) {
  fn(in: Input(i)) {
    case in.tokens {
      [] -> Error(UnexpectedEndOfInput(in.cursor, ["any token"]))
      [token, ..rest] -> ok(Input(rest, in.cursor + 1), token)
    }
  }
}

/// Consumes the end of the input and returns a Nil value. Fails if there is any input left.
pub fn eof() -> Parser(i, Nil) {
  fn(in: Input(i)) {
    case in.tokens {
      [] -> ok(in, Nil)
      [token, ..] -> Error(UnexpectedToken(in.cursor, ["end of input"], token))
    }
  }
}

/// A predicate function that returns a boolean value for a given input item of type `i`.
pub type Predicate(i) =
  fn(i) -> Bool

/// Consumes a single item from the input that satisfies the given predicate function.
pub fn satisfying(f: Predicate(i)) -> Parser(i, i) {
  fn(in: Input(i)) {
    case in.tokens {
      [] -> Error(UnexpectedEndOfInput(in.cursor, []))
      [token, ..rest] ->
        case f(token) {
          True -> ok(Input(rest, in.cursor + 1), token)
          False -> Error(UnexpectedToken(in.cursor, [], token))
        }
    }
  }
}

/// Consumes a single item from the input that is equal to the given item.
pub fn just(item: i) -> Parser(i, i) {
  fn(in: Input(i)) {
    case in.tokens {
      [] -> Error(UnexpectedEndOfInput(in.cursor, [string.inspect(item)]))
      [token, ..rest] if token == item -> ok(Input(rest, in.cursor + 1), item)
      [token, ..] ->
        Error(UnexpectedToken(in.cursor, [string.inspect(item)], token))
    }
  }
}

// Applies both parsers and returns a tuple of the results
pub fn pair(
  parser_1 p1: Parser(i, a),
  parser_2 p2: Parser(i, b),
) -> Parser(i, #(a, b)) {
  fn(in: Input(i)) {
    use parsed_1 <- continue(p1(in))
    use parsed_2 <- continue(p2(parsed_1.input))
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
      use parsed <- continue(parser(input))
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
    use parsed_1 <- continue(p1(in))
    use parsed_2 <- continue(p2(parsed_1.input))
    ok(parsed_2.input, parsed_1.value)
  }
}

/// Applies the first parser and then the second parser, returning the result of the second parser.
pub fn right(
  parser_1 p1: Parser(i, a),
  parser_2 p2: Parser(i, b),
) -> Parser(i, b) {
  fn(in: Input(i)) {
    use parsed_1 <- continue(p1(in))
    use parsed_2 <- continue(p2(parsed_1.input))
    ok(parsed_2.input, parsed_2.value)
  }
}

/// Applies the given parser zero or more times.
///
/// Stops as soon as the parser fails or succeeds without consuming any input.
pub fn many0(parser: Parser(i, a)) -> Parser(i, List(a)) {
  fn(in: Input(i)) { do_many(parser, in, [], None) }
}

fn do_many(
  parser: Parser(i, a),
  in: Input(i),
  acc: List(a),
  recovered: Option(ParseError(i)),
) -> ParseResult(i, List(a)) {
  case parser(in) {
    Ok(parsed) if parsed.input.cursor > in.cursor -> {
      let recovered = merge_optional_errors(recovered, parsed.furthest_error)
      let recovered = relevant(recovered, parsed.input.cursor)
      do_many(parser, parsed.input, [parsed.value, ..acc], recovered)
    }
    Ok(parsed) -> {
      let recovered = merge_optional_errors(recovered, parsed.furthest_error)
      Ok(Parsed(in, list.reverse(acc), recovered))
    }
    Error(error) -> {
      let recovered = merge_optional_errors(recovered, Some(error))
      Ok(Parsed(in, list.reverse(acc), recovered))
    }
  }
}

/// Applies the given parser one or more times.
pub fn many1(parser: Parser(i, a)) -> Parser(i, List(a)) {
  fn(in: Input(i)) {
    use parsed <- continue(parser(in))
    use rest <- continue(many0(parser)(parsed.input))
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
  |> map_error(fn(error) {
    with_expected(error, list.map(items, string.inspect))
  })
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
/// If all fail, returns the error that got furthest.
pub fn choice(parsers: List(Parser(i, a))) -> Parser(i, a) {
  fn(in: Input(i)) { do_choice(parsers, in, None) }
}

fn do_choice(
  parsers: List(Parser(i, a)),
  in: Input(i),
  error: Option(ParseError(i)),
) -> ParseResult(i, a) {
  case parsers, error {
    [], Some(error) -> Error(error)
    [], None -> Error(error_at(in, []))
    [parser, ..rest], _ ->
      case parser(in) {
        Ok(parsed) as result ->
          case error {
            Some(error) if error.position >= parsed.input.cursor ->
              Ok(recover(parsed, Some(error)))
            _ -> result
          }
        Error(parser_error) ->
          do_choice(rest, in, merge_optional_errors(error, Some(parser_error)))
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
      Error(error) -> Ok(Parsed(in, [], Some(error)))
      result -> {
        use parsed <- continue(result)
        use rest <- continue(many0(right(separator, parser))(parsed.input))
        ok(rest.input, [parsed.value, ..rest.value])
      }
    }
  }
}

/// Parses one or more occurrences of the given parser separated by the given separator.
pub fn sep_by1(
  parser: Parser(i, a),
  separator: Parser(i, b),
) -> Parser(i, List(a)) {
  fn(input: Input(i)) {
    use parsed <- continue(parser(input))
    use rest <- continue(many0(
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
      Ok(parsed) ->
        Ok(Parsed(parsed.input, Some(parsed.value), parsed.furthest_error))
      Error(error) -> Ok(Parsed(in, None, Some(error)))
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
    use parsed <- result.try(parser(in))
    let consumed = list.take(in.tokens, parsed.input.cursor - in.cursor)
    Ok(Parsed(parsed.input, consumed, parsed.furthest_error))
  }
}
