import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pears.{
  type ParseError, type Parser, type Step, type StepResult, Custom, Span, Step,
  UnexpectedEndOfInput, UnexpectedToken, merge_errors, new_parser, ok, run,
  with_expected,
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
fn recover(parsed: Step(i, a), error: Option(ParseError(i))) -> Step(i, a) {
  case error {
    None -> parsed
    Some(error) ->
      case error.position < input.position(parsed.input) {
        True -> parsed
        False ->
          Step(
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
  result: StepResult(i, a),
  next: fn(Step(i, a)) -> StepResult(i, b),
) -> StepResult(i, b) {
  case result {
    Error(error) -> Error(error)
    Ok(Step(furthest_error: None, ..) as parsed) -> next(parsed)
    Ok(Step(furthest_error: Some(recovered), ..) as parsed) ->
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
  new_parser(fn(in: Input(i)) { ok(in, value) })
}

/// Fails at the current position with `message`.
///
/// ```gleam
/// import pears.{Custom}
///
/// assert pears.parse_string("a", fail("not supported")) == Error(Custom(0, "not supported"))
/// ```
pub fn fail(message: String) -> Parser(i, a) {
  new_parser(fn(in: Input(i)) { Error(Custom(input.position(in), message)) })
}

/// Runs the parser and passes its result to `next`, which returns the parser to
/// run on the rest of the input. Works well with `use`:
///
/// ```gleam
/// import pears
/// import pears/chars
///
/// let integer = {
///   use sign <- then(optional(token("-")))
///   use number <- then(chars.natural())
///   case sign {
///     Some(_) -> succeed(-number)
///     None -> succeed(number)
///   }
/// }
///
/// assert pears.parse_string_all("-42", integer) == Ok(-42)
/// ```
pub fn then(parser: Parser(i, a), next: fn(a) -> Parser(i, b)) -> Parser(i, b) {
  new_parser(fn(in: Input(i)) {
    use parsed <- continue(run(parser, in))
    run(next(parsed.value), parsed.input)
  })
}

/// Maps the result of a parser with a function that can fail. If it returns
/// `Error(message)`, parsing fails with that message at the position where the
/// parser started.
///
/// ```gleam
/// import pears.{Custom}
/// import pears/chars
///
/// let byte =
///   try_map(chars.natural(), fn(n) {
///     case n < 256 {
///       True -> Ok(n)
///       False -> Error("number must be below 256")
///     }
///   })
/// assert pears.parse_string_all("255", byte) == Ok(255)
/// assert pears.parse_string_all("256", byte) == Error(Custom(0, "number must be below 256"))
/// ```
pub fn try_map(
  parser: Parser(i, a),
  fun: fn(a) -> Result(b, String),
) -> Parser(i, b) {
  new_parser(fn(in: Input(i)) {
    use step <- result.try(run(parser, in))
    case fun(step.value) {
      Ok(value) -> Ok(Step(step.input, value, step.furthest_error))
      Error(message) -> Error(Custom(input.position(in), message))
    }
  })
}

/// Maps the result of a parser to a new value using a mapper function.
pub fn map(parser: Parser(i, a), fun: fn(a) -> b) -> Parser(i, b) {
  new_parser(fn(input: Input(i)) {
    run(parser, input)
    |> result.map(fn(parsed) {
      Step(
        input: parsed.input,
        value: fun(parsed.value),
        furthest_error: parsed.furthest_error,
      )
    })
  })
}

/// Maps the error of a parser to a new error using a mapper function.
pub fn map_error(
  parser: Parser(i, a),
  fun: fn(ParseError(i)) -> ParseError(i),
) -> Parser(i, a) {
  new_parser(fn(input: Input(i)) {
    run(parser, input)
    |> result.map_error(fun)
  })
}

/// Reports `name` as expected when the parser fails without consuming input.
pub fn label(parser: Parser(i, a), name: String) -> Parser(i, a) {
  new_parser(fn(in: Input(i)) {
    let position = input.position(in)
    case run(parser, in) {
      Error(error) if error.position == position ->
        Error(with_expected(error, [name]))
      Ok(Step(furthest_error: Some(error), ..) as parsed)
        if error.position == position
      -> Ok(Step(..parsed, furthest_error: Some(with_expected(error, [name]))))
      result -> result
    }
  })
}

/// Runs the parser without consuming any input.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("a", pair(peek(token("a")), token("a"))) == Ok(#("a", "a"))
/// ```
pub fn peek(parser: Parser(i, a)) -> Parser(i, a) {
  new_parser(fn(in: Input(i)) {
    case run(parser, in) {
      Ok(parsed) -> ok(in, parsed.value)
      Error(_) as error -> error
    }
  })
}

/// Succeeds without consuming any input if the parser fails, and fails if it succeeds.
///
/// ```gleam
/// import pears
/// import pears/chars
///
/// let letter = satisfying(fn(c) { string.contains("abcdefghijklmnopqrstuvwxyz", c) })
/// let keyword = then_skip(chars.string("let"), not_followed_by(letter))
/// let assert Ok(_) = pears.parse_string("let x", keyword)
/// let assert Error(_) = pears.parse_string("letter", keyword)
/// ```
pub fn not_followed_by(parser: Parser(i, a)) -> Parser(i, Nil) {
  new_parser(fn(in: Input(i)) {
    case run(parser, in) {
      Ok(_) -> Error(error_at(in, []))
      Error(_) -> ok(in, Nil)
    }
  })
}

/// Leaves the parser out of error messages, e.g. for optional whitespace.
pub fn hidden(parser: Parser(i, a)) -> Parser(i, a) {
  new_parser(fn(in: Input(i)) {
    let position = input.position(in)
    case run(parser, in) {
      Ok(parsed) -> Ok(Step(..parsed, furthest_error: None))
      Error(error) if error.position == position ->
        Error(with_expected(error, []))
      Error(error) -> Error(error)
    }
  })
}

/// Maps the result of a parser to a constant value.
pub fn replace(parser: Parser(i, a), value: b) -> Parser(i, b) {
  map(parser, fn(_) { value })
}

/// Tries to apply the first parser, if it fails it applies the second parser.
pub fn or(first: Parser(i, a), second: Parser(i, a)) -> Parser(i, a) {
  new_parser(fn(input: Input(i)) {
    case run(first, input) {
      Ok(_) as result -> result
      Error(error_1) ->
        case run(second, input) {
          Ok(parsed) as result ->
            case error_1.position < input.position(parsed.input) {
              True -> result
              False -> Ok(recover(parsed, Some(error_1)))
            }
          Error(error_2) -> Error(merge_errors(error_1, error_2))
        }
    }
  })
}

/// Consumes any single item from the input except for the end of file.
pub fn any() -> Parser(i, i) {
  new_parser(fn(in: Input(i)) {
    case input.tokens(in) {
      [] -> Error(UnexpectedEndOfInput(input.position(in), ["any token"]))
      [token, ..] -> ok(input.next(in), token)
    }
  })
}

/// Consumes the end of the input and returns a Nil value. Fails if there is any input left.
pub fn eof() -> Parser(i, Nil) {
  new_parser(fn(in: Input(i)) {
    case input.tokens(in) {
      [] -> ok(in, Nil)
      [token, ..] ->
        Error(UnexpectedToken(input.position(in), ["end of input"], token))
    }
  })
}

/// Consumes a single item from the input that satisfies the given predicate function.
pub fn satisfying(predicate: fn(i) -> Bool) -> Parser(i, i) {
  new_parser(fn(in: Input(i)) {
    case input.tokens(in) {
      [] -> Error(UnexpectedEndOfInput(input.position(in), []))
      [token, ..] ->
        case predicate(token) {
          True -> ok(input.next(in), token)
          False -> Error(UnexpectedToken(input.position(in), [], token))
        }
    }
  })
}

/// Consumes a single item from the input that is equal to the given item.
pub fn token(item: i) -> Parser(i, i) {
  new_parser(fn(in: Input(i)) {
    case input.tokens(in) {
      [] ->
        Error(UnexpectedEndOfInput(input.position(in), [string.inspect(item)]))
      [token, ..] if token == item -> ok(input.next(in), item)
      [token, ..] ->
        Error(UnexpectedToken(input.position(in), [string.inspect(item)], token))
    }
  })
}

/// Applies both parsers and returns a tuple of the results.
pub fn pair(first: Parser(i, a), second: Parser(i, b)) -> Parser(i, #(a, b)) {
  new_parser(fn(in: Input(i)) {
    use parsed_1 <- continue(run(first, in))
    use parsed_2 <- continue(run(second, parsed_1.input))
    ok(parsed_2.input, #(parsed_1.value, parsed_2.value))
  })
}

/// Applies the given parsers in sequence and returns a list of the results
pub fn seq(parsers: List(Parser(i, a))) -> Parser(i, List(a)) {
  new_parser(fn(input: Input(i)) { do_sequence(parsers, input, []) })
}

fn do_sequence(
  parsers: List(Parser(i, a)),
  input: Input(i),
  acc: List(a),
) -> StepResult(i, List(a)) {
  case parsers {
    [] -> ok(input, list.reverse(acc))
    [parser, ..rest] -> {
      use parsed <- continue(run(parser, input))
      do_sequence(rest, parsed.input, [parsed.value, ..acc])
    }
  }
}

/// Applies the first parser and then the second parser, returning the result of the first parser.
pub fn then_skip(first: Parser(i, a), second: Parser(i, b)) -> Parser(i, a) {
  new_parser(fn(in: Input(i)) {
    use parsed_1 <- continue(run(first, in))
    use parsed_2 <- continue(run(second, parsed_1.input))
    ok(parsed_2.input, parsed_1.value)
  })
}

/// Applies the first parser and then the second parser, returning the result of the second parser.
pub fn skip_then(first: Parser(i, a), second: Parser(i, b)) -> Parser(i, b) {
  new_parser(fn(in: Input(i)) {
    use parsed_1 <- continue(run(first, in))
    use parsed_2 <- continue(run(second, parsed_1.input))
    ok(parsed_2.input, parsed_2.value)
  })
}

/// Applies the given parser zero or more times.
///
/// Stops as soon as the parser fails or succeeds without consuming any input.
pub fn many0(parser: Parser(i, a)) -> Parser(i, List(a)) {
  new_parser(fn(in: Input(i)) { do_many(parser, in, [], None) })
}

fn do_many(
  parser: Parser(i, a),
  in: Input(i),
  acc: List(a),
  recovered: Option(ParseError(i)),
) -> StepResult(i, List(a)) {
  case run(parser, in) {
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
        False -> Ok(Step(in, list.reverse(acc), recovered))
      }
    }
    Error(error) -> {
      let recovered = merge_optional_errors(recovered, Some(error))
      Ok(Step(in, list.reverse(acc), recovered))
    }
  }
}

/// Applies the given parser one or more times.
pub fn many1(parser: Parser(i, a)) -> Parser(i, List(a)) {
  new_parser(fn(in: Input(i)) {
    use parsed <- continue(run(parser, in))
    use rest <- continue(run(many0(parser), parsed.input))
    ok(rest.input, [parsed.value, ..rest.value])
  })
}

/// Applies the given parser exactly `n` times.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("aaa", exactly(token("a"), 3)) == Ok(["a", "a", "a"])
/// let assert Error(_) = pears.parse_string_all("aa", exactly(token("a"), 3))
/// ```
pub fn exactly(parser: Parser(i, a), n: Int) -> Parser(i, List(a)) {
  new_parser(fn(in: Input(i)) { do_repeat(parser, in, [], 0, n, Some(n), None) })
}

/// Applies the given parser `n` or more times.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("aaa", at_least(token("a"), 2)) == Ok(["a", "a", "a"])
/// let assert Error(_) = pears.parse_string_all("a", at_least(token("a"), 2))
/// ```
pub fn at_least(parser: Parser(i, a), n: Int) -> Parser(i, List(a)) {
  new_parser(fn(in: Input(i)) { do_repeat(parser, in, [], 0, n, None, None) })
}

/// Applies the given parser up to `n` times.
///
/// ```gleam
/// import pears
///
/// let assert Ok(parsed) = pears.parse_string("aaa", at_most(token("a"), 2))
/// assert parsed.value == ["a", "a"]
/// ```
pub fn at_most(parser: Parser(i, a), n: Int) -> Parser(i, List(a)) {
  new_parser(fn(in: Input(i)) { do_repeat(parser, in, [], 0, 0, Some(n), None) })
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
) -> StepResult(i, List(a)) {
  case max {
    Some(max) if count >= max -> Ok(Step(in, list.reverse(acc), recovered))
    _ ->
      case run(parser, in) {
        Ok(parsed) -> {
          let recovered =
            merge_optional_errors(recovered, parsed.furthest_error)
          let position = input.position(parsed.input)
          case position > input.position(in), count >= min {
            False, True -> Ok(Step(in, list.reverse(acc), recovered))
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
              Ok(Step(
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
/// let comment = skip_then(chars.string("/*"), many_till(any(), chars.string("*/")))
/// assert pears.parse_string_all("/*hi*/", comment) == Ok(["h", "i"])
/// ```
pub fn many_till(
  parser: Parser(i, a),
  end: Parser(i, b),
) -> Parser(i, List(a)) {
  new_parser(fn(in: Input(i)) { do_many_till(parser, end, in, [], None) })
}

fn do_many_till(
  parser: Parser(i, a),
  end: Parser(i, b),
  in: Input(i),
  acc: List(a),
  recovered: Option(ParseError(i)),
) -> StepResult(i, List(a)) {
  case run(end, in) {
    Ok(parsed_end) ->
      Ok(recover(
        Step(parsed_end.input, list.reverse(acc), parsed_end.furthest_error),
        recovered,
      ))
    Error(end_error) -> {
      let recovered = merge_optional_errors(recovered, Some(end_error))
      case run(parser, in) {
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
///     |> sep_by0(token(","))
///     |> between(token("["), token("]"))
///     |> map(Node)
///   or(leaf, node)
/// }
/// ```
pub fn lazy(f: fn() -> Parser(i, a)) -> Parser(i, a) {
  new_parser(fn(input) { run(f(), input) })
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
  |> skip_then(parser)
  |> then_skip(close)
}

/// Tries to apply the given parsers in order and returns the result of the first one that succeeds.
/// If all fail, returns the error that got furthest.
pub fn choice(parsers: List(Parser(i, a))) -> Parser(i, a) {
  new_parser(fn(in: Input(i)) { do_choice(parsers, in, None) })
}

fn do_choice(
  parsers: List(Parser(i, a)),
  in: Input(i),
  error: Option(ParseError(i)),
) -> StepResult(i, a) {
  case parsers, error {
    [], Some(error) -> Error(error)
    [], None -> Error(error_at(in, []))
    [parser, ..rest], _ ->
      case run(parser, in) {
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
/// let minus = replace(token("-"), int.subtract)
/// assert pears.parse_string_all("10-2-3", chain_left(chars.natural(), minus)) == Ok(5)
/// ```
pub fn chain_left(
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

/// Like `chain_left`, but combines the values from right to left, so `10-2-3`
/// becomes `10-(2-3)`:
///
/// ```gleam
/// import gleam/int
/// import pears
/// import pears/chars
///
/// let minus = replace(token("-"), int.subtract)
/// assert pears.parse_string_all("10-2-3", chain_right(chars.natural(), minus)) == Ok(11)
/// ```
pub fn chain_right(
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
  new_parser(fn(in: Input(i)) {
    case run(parser, in) {
      Error(error) -> Ok(Step(in, [], Some(error)))
      result -> {
        use parsed <- continue(result)
        use rest <- continue(run(
          many0(skip_then(separator, parser)),
          parsed.input,
        ))
        ok(rest.input, [parsed.value, ..rest.value])
      }
    }
  })
}

/// Parses one or more occurrences of the given parser separated by the given separator.
pub fn sep_by1(
  parser: Parser(i, a),
  separator: Parser(i, b),
) -> Parser(i, List(a)) {
  new_parser(fn(input: Input(i)) {
    use parsed <- continue(run(parser, input))
    use rest <- continue(run(many0(skip_then(separator, parser)), parsed.input))
    ok(rest.input, [parsed.value, ..rest.value])
  })
}

/// Like `sep_by0`, but allows a trailing separator.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("a,a,", sep_end_by0(token("a"), token(","))) == Ok(["a", "a"])
/// assert pears.parse_string_all("", sep_end_by0(token("a"), token(","))) == Ok([])
/// ```
pub fn sep_end_by0(
  parser: Parser(i, a),
  separator: Parser(i, b),
) -> Parser(i, List(a)) {
  or(sep_end_by1(parser, separator), succeed([]))
}

/// Like `sep_by1`, but allows a trailing separator.
///
/// ```gleam
/// import pears
///
/// assert pears.parse_string_all("a,a,", sep_end_by1(token("a"), token(","))) == Ok(["a", "a"])
/// let assert Error(_) = pears.parse_string_all(",", sep_end_by1(token("a"), token(",")))
/// ```
pub fn sep_end_by1(
  parser: Parser(i, a),
  separator: Parser(i, b),
) -> Parser(i, List(a)) {
  then_skip(sep_by1(parser, separator), optional(separator))
}

/// Applies the given parser and wraps the result in an `Option`,
/// returning `None` if the parser fails instead of an error.
pub fn optional(parser: Parser(i, a)) -> Parser(i, Option(a)) {
  new_parser(fn(in: Input(i)) {
    case run(parser, in) {
      Ok(parsed) ->
        Ok(Step(parsed.input, Some(parsed.value), parsed.furthest_error))
      Error(error) -> Ok(Step(in, None, Some(error)))
    }
  })
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

/// Returns the parsed value together with the span of tokens the parser consumed.
///
/// ```gleam
/// import pears.{Span}
/// import pears/chars
///
/// let parser = skip_then(chars.string("let "), with_span(chars.string("x")))
/// assert pears.parse_string_all("let x", parser) == Ok(#("x", Span(4, 5)))
/// ```
pub fn with_span(parser: Parser(i, a)) -> Parser(i, #(a, pears.Span)) {
  new_parser(fn(in: Input(i)) {
    let start = input.position(in)
    use parsed <- result.map(run(parser, in))
    let span = Span(start, input.position(parsed.input))
    Step(parsed.input, #(parsed.value, span), parsed.furthest_error)
  })
}

/// Creates a parser that returns the consumed tokens instead of its parsed value.
pub fn recognize(parser: Parser(i, a)) -> Parser(i, List(i)) {
  new_parser(fn(in: Input(i)) {
    use parsed <- result.try(run(parser, in))
    let consumed =
      list.take(
        input.tokens(in),
        input.position(parsed.input) - input.position(in),
      )
    Ok(Step(parsed.input, consumed, parsed.furthest_error))
  })
}
