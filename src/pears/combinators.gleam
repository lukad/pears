import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pears.{
  type ParseError, type ParseResult, type Parsed, type Parser, Parsed,
  UnexpectedEndOfInput, UnexpectedToken, merge_errors, ok, with_expected,
}
import pears/input.{type Input}

fn error_at(in: Input(i), expected: List(String)) -> ParseError(i) {
  case input.get(in) {
    None -> UnexpectedEndOfInput(input.position(in), expected)
    Some(token) -> UnexpectedToken(input.position(in), expected, token)
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

/// Drops a recovered error before `position`, since any later error wins over it.
fn relevant(
  error: Option(ParseError(i)),
  position: Int,
) -> Option(ParseError(i)) {
  case error {
    Some(error) if error.position < position -> None
    _ -> error
  }
}

/// Adds a recovered error to a successful result. `parsed.furthest_error` is
/// never before its position, so only `error` needs checking.
fn recover(parsed: Parsed(i, a), error: Option(ParseError(i))) -> Parsed(i, a) {
  case error {
    None -> parsed
    Some(error) ->
      case error.position < input.position(parsed.input) {
        True -> parsed
        False ->
          Parsed(
            ..parsed,
            furthest_error: merge_optional_errors(
              Some(error),
              parsed.furthest_error,
            ),
          )
      }
  }
}

fn add_recovered(
  error: ParseError(i),
  recovered: Option(ParseError(i)),
) -> ParseError(i) {
  case recovered {
    None -> error
    Some(recovered) -> merge_errors(recovered, error)
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

/// Returns `value` without consuming any input.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("", succeed(1)) == Ok(1)
/// ```
pub fn succeed(value: a) -> Parser(i, a) {
  fn(in: Input(i)) { ok(in, value) }
}

/// Fails at the current position, reporting `expected` as what was expected.
///
/// ```gleam
/// import pears.{UnexpectedToken}
///
/// assert pears.parse_string("a", fail("digit")) == Error(UnexpectedToken(0, ["digit"], "a"))
/// ```
pub fn fail(expected: String) -> Parser(i, a) {
  fn(in: Input(i)) { Error(error_at(in, [expected])) }
}

/// Runs the parser and passes its result to `next`, which returns the parser to
/// run on the rest of the input. Works well with `use`:
///
/// ```gleam
/// import pears
/// import pears/chars
///
/// let integer = {
///   use sign <- then(maybe(just("-")))
///   use number <- then(chars.number())
///   case sign {
///     Some(_) -> succeed(-number)
///     None -> succeed(number)
///   }
/// }
///
/// assert pears.parse_string_all("-42", integer) == Ok(-42)
/// ```
pub fn then(parser: Parser(i, a), next: fn(a) -> Parser(i, b)) -> Parser(i, b) {
  fn(in: Input(i)) {
    use parsed <- continue(parser(in))
    next(parsed.value)(parsed.input)
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
    let position = input.position(in)
    case parser(in) {
      Error(error) if error.position == position ->
        Error(with_expected(error, [label]))
      Ok(Parsed(furthest_error: Some(error), ..) as parsed)
        if error.position == position
      ->
        Ok(
          Parsed(..parsed, furthest_error: Some(with_expected(error, [label]))),
        )
      result -> result
    }
  }
}

/// Runs the parser without consuming any input.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("a", pair(peek(just("a")), just("a"))) == Ok(#("a", "a"))
/// ```
pub fn peek(parser: Parser(i, a)) -> Parser(i, a) {
  fn(in: Input(i)) {
    case parser(in) {
      Ok(parsed) -> ok(in, parsed.value)
      Error(_) as error -> error
    }
  }
}

/// Succeeds without consuming any input if the parser fails, and fails if it succeeds.
///
/// ```gleam
/// import pears
/// import pears/chars
///
/// let letter = satisfying(fn(c) { string.contains("abcdefghijklmnopqrstuvwxyz", c) })
/// let keyword = left(chars.string("let"), not_followed_by(letter))
/// let assert Ok(_) = pears.parse_string("let x", keyword)
/// let assert Error(_) = pears.parse_string("letter", keyword)
/// ```
pub fn not_followed_by(parser: Parser(i, a)) -> Parser(i, Nil) {
  fn(in: Input(i)) {
    case parser(in) {
      Ok(_) -> Error(error_at(in, []))
      Error(_) -> ok(in, Nil)
    }
  }
}

/// Leaves the parser out of error messages, e.g. for optional whitespace.
pub fn hidden(parser: Parser(i, a)) -> Parser(i, a) {
  fn(in: Input(i)) {
    let position = input.position(in)
    case parser(in) {
      Ok(parsed) -> Ok(Parsed(..parsed, furthest_error: None))
      Error(error) if error.position == position ->
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
          Ok(parsed) as result ->
            case error_1.position < input.position(parsed.input) {
              True -> result
              False -> Ok(recover(parsed, Some(error_1)))
            }
          Error(error_2) -> Error(merge_errors(error_1, error_2))
        }
    }
  }
}

/// Consumes any single item from the input except for the end of file.
pub fn any() -> Parser(i, i) {
  fn(in: Input(i)) {
    case input.tokens(in) {
      [] -> Error(UnexpectedEndOfInput(input.position(in), ["any token"]))
      [token, ..] -> ok(input.next(in), token)
    }
  }
}

/// Consumes the end of the input and returns a Nil value. Fails if there is any input left.
pub fn eof() -> Parser(i, Nil) {
  fn(in: Input(i)) {
    case input.tokens(in) {
      [] -> ok(in, Nil)
      [token, ..] ->
        Error(UnexpectedToken(input.position(in), ["end of input"], token))
    }
  }
}

/// A predicate function that returns a boolean value for a given input item of type `i`.
pub type Predicate(i) =
  fn(i) -> Bool

/// Consumes a single item from the input that satisfies the given predicate function.
pub fn satisfying(f: Predicate(i)) -> Parser(i, i) {
  fn(in: Input(i)) {
    case input.tokens(in) {
      [] -> Error(UnexpectedEndOfInput(input.position(in), []))
      [token, ..] ->
        case f(token) {
          True -> ok(input.next(in), token)
          False -> Error(UnexpectedToken(input.position(in), [], token))
        }
    }
  }
}

/// Consumes a single item from the input that is equal to the given item.
pub fn just(item: i) -> Parser(i, i) {
  fn(in: Input(i)) {
    case input.tokens(in) {
      [] ->
        Error(UnexpectedEndOfInput(input.position(in), [string.inspect(item)]))
      [token, ..] if token == item -> ok(input.next(in), item)
      [token, ..] ->
        Error(UnexpectedToken(input.position(in), [string.inspect(item)], token))
    }
  }
}

/// Applies both parsers and returns a tuple of the results.
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
    Ok(parsed) -> {
      let recovered = merge_optional_errors(recovered, parsed.furthest_error)
      let position = input.position(parsed.input)
      case position > input.position(in) {
        True ->
          do_many(
            parser,
            parsed.input,
            [parsed.value, ..acc],
            relevant(recovered, position),
          )
        False -> Ok(Parsed(in, list.reverse(acc), recovered))
      }
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

/// Applies the given parser exactly `n` times.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("aaa", exactly(just("a"), 3)) == Ok(["a", "a", "a"])
/// let assert Error(_) = pears.parse_string_all("aa", exactly(just("a"), 3))
/// ```
pub fn exactly(parser: Parser(i, a), n: Int) -> Parser(i, List(a)) {
  fn(in: Input(i)) { do_repeat(parser, in, [], 0, n, Some(n), None) }
}

/// Applies the given parser `n` or more times.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("aaa", at_least(just("a"), 2)) == Ok(["a", "a", "a"])
/// let assert Error(_) = pears.parse_string_all("a", at_least(just("a"), 2))
/// ```
pub fn at_least(parser: Parser(i, a), n: Int) -> Parser(i, List(a)) {
  fn(in: Input(i)) { do_repeat(parser, in, [], 0, n, None, None) }
}

/// Applies the given parser up to `n` times.
///
/// ```gleam
/// import pears
///
/// let assert Ok(parsed) = pears.parse_string("aaa", at_most(just("a"), 2))
/// assert parsed.value == ["a", "a"]
/// ```
pub fn at_most(parser: Parser(i, a), n: Int) -> Parser(i, List(a)) {
  fn(in: Input(i)) { do_repeat(parser, in, [], 0, 0, Some(n), None) }
}

/// Applies the parser at least `min` and at most `max` times. Like `many0`, it
/// stops at a match that consumes nothing once `min` is reached.
fn do_repeat(
  parser: Parser(i, a),
  in: Input(i),
  acc: List(a),
  count: Int,
  min: Int,
  max: Option(Int),
  recovered: Option(ParseError(i)),
) -> ParseResult(i, List(a)) {
  case max {
    Some(max) if count >= max -> Ok(Parsed(in, list.reverse(acc), recovered))
    _ ->
      case parser(in) {
        Ok(parsed) -> {
          let recovered =
            merge_optional_errors(recovered, parsed.furthest_error)
          let position = input.position(parsed.input)
          case position > input.position(in), count >= min {
            False, True -> Ok(Parsed(in, list.reverse(acc), recovered))
            _, _ ->
              do_repeat(
                parser,
                parsed.input,
                [parsed.value, ..acc],
                count + 1,
                min,
                max,
                relevant(recovered, position),
              )
          }
        }
        Error(error) ->
          case count >= min {
            True ->
              Ok(Parsed(
                in,
                list.reverse(acc),
                merge_optional_errors(recovered, Some(error)),
              ))
            False -> Error(add_recovered(error, recovered))
          }
      }
  }
}

/// Applies the given parser until `end` succeeds, returning the results of the
/// parser. `end` is consumed but its result is dropped.
///
/// ```gleam
/// import pears
/// import pears/chars
///
/// let comment = right(chars.string("/*"), many_till(any(), chars.string("*/")))
/// assert pears.parse_string_all("/*hi*/", comment) == Ok(["h", "i"])
/// ```
pub fn many_till(
  parser: Parser(i, a),
  end: Parser(i, b),
) -> Parser(i, List(a)) {
  fn(in: Input(i)) { do_many_till(parser, end, in, [], None) }
}

fn do_many_till(
  parser: Parser(i, a),
  end: Parser(i, b),
  in: Input(i),
  acc: List(a),
  recovered: Option(ParseError(i)),
) -> ParseResult(i, List(a)) {
  case end(in) {
    Ok(parsed_end) ->
      Ok(recover(
        Parsed(parsed_end.input, list.reverse(acc), parsed_end.furthest_error),
        recovered,
      ))
    Error(end_error) -> {
      let recovered = merge_optional_errors(recovered, Some(end_error))
      case parser(in) {
        Ok(parsed) -> {
          let position = input.position(parsed.input)
          case position > input.position(in) {
            True -> {
              let recovered =
                merge_optional_errors(recovered, parsed.furthest_error)
              do_many_till(
                parser,
                end,
                parsed.input,
                [parsed.value, ..acc],
                relevant(recovered, position),
              )
            }
            False -> Error(add_recovered(end_error, recovered))
          }
        }
        Error(error) -> Error(add_recovered(error, recovered))
      }
    }
  }
}

/// Lazily applies the given parser allowing for recursive parsers.
///
/// ## Examples
///
/// Parsing a recursive list of chars:
///
/// ```gleam,ignore
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

/// Applies the given parser between the open and close parsers, returning the result of the inner parser.
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
            Some(error) ->
              case error.position < input.position(parsed.input) {
                True -> result
                False -> Ok(recover(parsed, Some(error)))
              }
            None -> result
          }
        Error(parser_error) ->
          do_choice(rest, in, merge_optional_errors(error, Some(parser_error)))
      }
  }
}

/// Parses one or more occurrences of the given parser separated by `operator`,
/// combining the values from left to right with the functions `operator` returns.
/// Use it for left-associative operators like `-`:
///
/// ```gleam
/// import gleam/int
/// import pears
/// import pears/chars
///
/// let minus = to(just("-"), int.subtract)
/// assert pears.parse_string_all("10-2-3", chainl1(chars.number(), minus)) == Ok(5)
/// ```
pub fn chainl1(
  parser: Parser(i, a),
  operator: Parser(i, fn(a, a) -> a),
) -> Parser(i, a) {
  use first <- then(parser)
  use rest <- map(many0(pair(operator, parser)))
  list.fold(rest, first, fn(acc, item) {
    let #(op, value) = item
    op(acc, value)
  })
}

/// Like `chainl1`, but combines the values from right to left, so `10-2-3`
/// becomes `10-(2-3)`:
///
/// ```gleam
/// import gleam/int
/// import pears
/// import pears/chars
///
/// let minus = to(just("-"), int.subtract)
/// assert pears.parse_string_all("10-2-3", chainr1(chars.number(), minus)) == Ok(11)
/// ```
pub fn chainr1(
  parser: Parser(i, a),
  operator: Parser(i, fn(a, a) -> a),
) -> Parser(i, a) {
  use first <- then(parser)
  use rest <- map(many0(pair(operator, parser)))
  case list.reverse(rest) {
    [] -> first
    [#(op, last), ..rest] -> {
      let #(op, acc) =
        list.fold(rest, #(op, last), fn(state, item) {
          let #(pending, acc) = state
          let #(op, value) = item
          #(op, pending(value, acc))
        })
      op(first, acc)
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

/// Like `sep_by0`, but allows a trailing separator.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("a,a,", sep_end_by0(just("a"), just(","))) == Ok(["a", "a"])
/// assert pears.parse_string_all("", sep_end_by0(just("a"), just(","))) == Ok([])
/// ```
pub fn sep_end_by0(
  parser: Parser(i, a),
  separator: Parser(i, b),
) -> Parser(i, List(a)) {
  alt(sep_end_by1(parser, separator), succeed([]))
}

/// Like `sep_by1`, but allows a trailing separator.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("a,a,", sep_end_by1(just("a"), just(","))) == Ok(["a", "a"])
/// let assert Error(_) = pears.parse_string_all(",", sep_end_by1(just("a"), just(",")))
/// ```
pub fn sep_end_by1(
  parser: Parser(i, a),
  separator: Parser(i, b),
) -> Parser(i, List(a)) {
  left(sep_by1(parser, separator), maybe(separator))
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

/// Creates a parser that returns the consumed tokens instead of its parsed value.
pub fn recognize(parser: Parser(i, a)) -> Parser(i, List(i)) {
  fn(in: Input(i)) {
    use parsed <- result.try(parser(in))
    let consumed =
      list.take(
        input.tokens(in),
        input.position(parsed.input) - input.position(in),
      )
    Ok(Parsed(parsed.input, consumed, parsed.furthest_error))
  }
}
