//// ## A parser combinator library for gleam
////
//// Writing a parser using pears is easy, you just combine functions that
//// parse smaller parts of the input into a function that parses the whole input.
////
//// Here's an example of a parser that parses the letter 'a', run with `parse_string`:
////
//// ```gleam
//// import pears.{UnexpectedToken}
//// import pears/chars
//// import pears/combinators.{alt, between, choice, just, left, many0, many1, map, pair, right, sep_by0, succeed, then, to}
////
//// let a_parser = just("a")
//// let assert Ok(parsed) = parse_string("abc", a_parser)
//// assert parsed.value == "a"
//// ```
////
//// It returns a `Result` with a `Parsed` record that holds the parsed value and the remaining input.
////
//// Under the hood all `parse_string` does is convert the input string into a list of graphemes and then
//// call the given parser, which is just a function, passing the input to it:
////
//// ```gleam
//// let input = input.new(string.to_graphemes("abc"))
//// let assert Ok(parsed) = just("a")(input)
//// assert parsed.value == "a"
//// ```
////
//// To parse the whole input and get just the value, use `parse_string_all`.
//// It fails if any input is left over:
////
//// ```gleam
//// assert parse_string_all("a", just("a")) == Ok("a")
//// assert parse_string_all("abc", just("a")) == Error(UnexpectedToken(1, ["end of input"], "b"))
//// ```
////
//// ### Combinators
////
//// Combining parsers using combinators is how you build more complex parsers.
//// A combinator is just a function that takes one or more parsers and returns a new parser.
////
//// Let's say we want to parse the letter 'a' followed by the letter 'b', we can use the `pair` combinator for that.
//// It runs the first parser and then the second one, returning both results as a tuple:
////
//// ```gleam
//// assert parse_string_all("ab", pair(just("a"), just("b"))) == Ok(#("a", "b"))
//// ```
////
//// To create parsers that are actually useful we need to be able to branch based on the input,
//// for that we can use the `alt` combinator:
////
//// ```gleam
//// let a_or_b_parser = alt(just("a"), just("b"))
//// assert parse_string_all("a", a_or_b_parser) == Ok("a")
//// assert parse_string_all("b", a_or_b_parser) == Ok("b")
//// ```
////
//// In cases where there are more than two options, we can use the `choice` combinator:
////
//// ```gleam
//// let a_b_or_c_parser = choice([just("a"), just("b"), just("c")])
//// assert parse_string_all("c", a_b_or_c_parser) == Ok("c")
//// ```
////
//// The next crucial combinators are `many0` and `many1`.
//// They allow us to parse zero or more or one or more repetitions of a parser:
////
//// ```gleam
//// let abc0_parser = many0(choice([just("a"), just("b"), just("c")]))
//// assert parse_string_all("cab", abc0_parser) == Ok(["c", "a", "b"])
//// assert parse_string_all("", abc0_parser) == Ok([])
//// ```
////
//// Sometimes we want to parse something and then ignore the result,
//// for that we can use the `left` and `right` combinators.
//// `left` keeps the result of the first parser and `right` the result of the second:
////
//// ```gleam
//// assert parse_string_all("ab", left(just("a"), just("b"))) == Ok("a")
//// assert parse_string_all("ab", right(just("a"), just("b"))) == Ok("b")
//// ```
////
//// Longer sequences are easier to write with `then` and Gleam's `use` syntax.
//// `succeed` returns a value without consuming any input:
////
//// ```gleam
//// let point = {
////   use x <- then(chars.number())
////   use _ <- then(just(","))
////   use y <- then(chars.number())
////   succeed(#(x, y))
//// }
//// assert parse_string_all("1,2", point) == Ok(#(1, 2))
//// ```
////
//// These building blocks are enough to build many combinators that can parse complex data structures.
//// For example the `sep_by0` and `sep_by1` combinators which can be used to parse lists of items
//// separated by a delimiter:
////
//// ```gleam
//// let letters = sep_by0(choice([just("a"), just("b"), just("c")]), just(","))
//// assert parse_string_all("a,b,c", letters) == Ok(["a", "b", "c"])
//// ```
////
//// ### Transforming the results
////
//// The `map` combinator transforms the result of a parser using a function.
//// Here we parse one or more digits and turn them into an `Int`, which is what `chars.number` does:
////
//// ```gleam
//// let number_parser =
////   many1(chars.digit())
////   |> map(fn(digits) {
////     let assert Ok(number) = int.parse(string.concat(digits))
////     number
////   })
//// assert parse_string_all("42", number_parser) == Ok(42)
//// ```
////
//// `to` is a shorthand for `map` that ignores the parsed value and returns a constant:
////
//// ```gleam
//// let bool_parser =
////   alt(to(chars.string("true"), True), to(chars.string("false"), False))
//// let bools_parser =
////   sep_by0(bool_parser, just(","))
////   |> between(just("["), just("]"))
//// assert parse_string_all("[true,false]", bools_parser) == Ok([True, False])
//// ```
////
//// ### Errors
////
//// When a parser fails it returns a `ParseError` with the position of the failing token,
//// what was expected there and what was found instead. `format_error` and
//// `chars.format_error` turn it into a message:
////
//// ```gleam
//// let source = "a,b;c"
//// let letters = sep_by0(choice([just("a"), just("b"), just("c")]), just(","))
//// let assert Error(error) = parse_string_all(source, letters)
//// assert chars.format_error(error, source) == "line 1, column 4: expected \",\" or end of input, found \";\""
//// ```
////
//// ### More examples
////
//// Please have a look at the tests for more complex examples, such as parsing JSON or Brainf*ck,
//// or a lexer followed by a parser over its tokens (`test/lexer_test.gleam`).

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import pears/input.{type Input}

/// Returned by a parser when it is successful. It contains the remaining input and the parsed value.
///
/// `furthest_error` is an error the parser recovered from, e.g. where `many0`
/// stopped. It gets merged into later errors to make their messages more complete.
pub type Parsed(i, a) {
  Parsed(input: Input(i), value: a, furthest_error: Option(ParseError(i)))
}

/// The tokens from `start` up to, but not including, `end`.
pub type Span {
  Span(start: Int, end: Int)
}

/// Returned by a parser when it fails. `position` is the index of the token
/// where parsing failed.
pub type ParseError(i) {
  UnexpectedEndOfInput(position: Int, expected: List(String))
  UnexpectedToken(position: Int, expected: List(String), found: i)
}

/// The result of a parser. It is either a `Parsed` or a `ParseError`.
pub type ParseResult(i, a) =
  Result(Parsed(i, a), ParseError(i))

/// The generic parser type. It's an alias for a function that takes an `Input(i)` and returns a `ParseResult(i, a)`.
pub type Parser(i, a) =
  fn(Input(i)) -> ParseResult(i, a)

/// Runs a parser on a list of tokens. The parser doesn't have to consume all of them.
pub fn parse(i: List(i), p: Parser(i, a)) -> ParseResult(i, a) {
  input.new(i)
  |> p()
}

/// Runs a parser on the graphemes of a string. The parser doesn't have to consume all of them.
pub fn parse_string(i: String, p: Parser(String, a)) -> ParseResult(String, a) {
  i
  |> string.to_graphemes()
  |> parse(p)
}

/// Runs a parser on a list of tokens and returns the parsed value.
/// Fails if any tokens are left over.
pub fn parse_all(i: List(i), p: Parser(i, a)) -> Result(a, ParseError(i)) {
  case parse(i, p) {
    Error(error) -> Error(error)
    Ok(Parsed(rest, value, furthest_error)) ->
      case input.tokens(rest), furthest_error {
        [], _ -> Ok(value)
        [token, ..], _ -> {
          let error =
            UnexpectedToken(input.position(rest), ["end of input"], token)
          case furthest_error {
            None -> Error(error)
            Some(furthest_error) -> Error(merge_errors(furthest_error, error))
          }
        }
      }
  }
}

/// Runs a parser on the graphemes of a string and returns the parsed value.
/// Fails if any graphemes are left over.
pub fn parse_string_all(
  i: String,
  p: Parser(String, a),
) -> Result(a, ParseError(String)) {
  i
  |> string.to_graphemes()
  |> parse_all(p)
}

/// Creates a successful parse result.
pub fn ok(input: Input(i), value: a) -> ParseResult(i, a) {
  Ok(Parsed(input, value, None))
}

/// Keeps the error that got furthest, combining expectations at the same position.
@internal
pub fn merge_errors(a: ParseError(i), b: ParseError(i)) -> ParseError(i) {
  case int.compare(a.position, b.position) {
    order.Gt -> a
    order.Lt -> b
    order.Eq ->
      with_expected(b, list.unique(list.append(a.expected, b.expected)))
  }
}

@internal
pub fn with_expected(
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

/// Formats a parse error, e.g. `position 3: expected "," or "]", found "x"`.
/// See `chars.format_error` for line and column numbers.
pub fn format_error(error: ParseError(i)) -> String {
  "position " <> int.to_string(error.position) <> ": " <> error_message(error)
}

/// Formats a parse error without its position, e.g. `expected "," or "]", found "x"`.
pub fn error_message(error: ParseError(i)) -> String {
  let found = case error {
    UnexpectedEndOfInput(_, _) -> "end of input"
    UnexpectedToken(_, _, found) -> string.inspect(found)
  }
  case error.expected {
    [] -> "unexpected " <> found
    expected ->
      "expected " <> join_alternatives(expected) <> ", found " <> found
  }
}

fn join_alternatives(alternatives: List(String)) -> String {
  case list.reverse(alternatives) {
    [] -> ""
    [only] -> only
    [last, ..rest] ->
      { rest |> list.reverse() |> string.join(", ") } <> " or " <> last
  }
}
