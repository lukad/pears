//// ## A parser combinator library for gleam
////
//// Writing a parser using pears is easy, you just combine functions that
//// parse smaller parts of the input into a function that parses the whole input.
////
//// Here's an example of a parser that parses the letter 'a':
////
//// ```gleam
//// let a_parser = just("a")
//// ```
////
//// We can run this parser using the `parse_string` function:
////
//// ```gleam
//// parse_string("abc", a_parser)
//// // => Ok(Parsed(["b", "c"], "a"))
//// ```
////
//// It returns a `Result` that gives us the remaining input (if any) and the parsed value when successful.
//// Here the remaining input is `["b", "c"]` and the parsed value is `"a"`.
////
//// Under the hood all `parse_string` does is convert the input string into a list of graphemes and then
//// call given parser, which is just a function, passing the input to it.
////
//// It is equivalent to the following:
////
//// ```gleam
//// let input = string.to_graphemes("abc")
//// a_parser()(input)
//// // => Ok(Parsed(["b", "c"], "a"))
//// ```
////
//// ### Combinators
////
//// Combining parsers using combinators is how you build more complex parsers.
//// A combinator is just a function that one or more parsers and returns a new parser.
////
//// Let's say we want to parse the letter 'a' followed by the letter 'b', we can use the `pair` combinator for that:
////
//// ```gleam
//// let ab_parser = pair(just("a"), just("b"))
//// parse_string("abc", ab_parser)
//// // => Ok(Parsed(["c"], [#("a", "b")]))
//// ```
////
//// The `pair` combinator takes two parsers and returns a new parser that runs the first parser and then the second
//// parser, returning both results as a tuple if both are successful.
////
//// To create parsers that are actually useful we need to be able to branch based on the input,
//// for that we can use the `alt` combinator:
////
//// ```gleam
//// let a_or_b_parser = alt(just("a"), just("b"))
//// parse_string("abc", a_or_b_parser)
//// // => Ok(Parsed(["b", "c"], "a"))
//// parse_string("cba", a_or_b_parser)
//// // => Ok(Parsed(["b", "a"], "c"))
//// ```
////
//// In cases where there are more than two options, we can use the `choice` combinator:
////
//// ```gleam
//// let a_b_or_c_parser = choice(just("a"), just("b"), just("c"))
//// parse_string("abc", a_b_or_c_parser)
//// // => Ok(Parsed(["b", "c"], "a"))
//// parse_string("bca", a_b_or_c_parser)
//// // => Ok(Parsed(["c", "a"], "b"))
//// parse_string("cab", a_b_or_c_parser)
//// // => Ok(Parsed(["a", "b"], "c"))
//// ```
////
//// The next crucial combinators are `many0` and `many1`.
//// They allow us to parse zero or more or one or more repetitions of a parser:
////
//// ```gleam
//// let abc0_parser = many0(a_b_or_c_parser)
//// parse_string("abc", abc0_parser)
//// // => Ok(Parsed([], ["a", "b", "c"]))
//// parse_string("cab", abc0_parser)
//// // => Ok(Parsed([], ["c", "a", "b"]))
//// parse_string("abcbcacab", abc0_parser)
//// // => Ok(Parsed([], ["a", "b", "c", "b", "c", "a", "c", "a", "b"]))
//// ```
////
//// Sometimes we want to parse something and then ignore the result,
//// for that we can use the `left` and `right` combinators.
////
//// In this example we parse the letter 'a' followed by the letter 'b' and ignore the result of the first parser:
////
//// ```gleam
//// let a_followed_by_b_parser = left(just("a"), just("b"))
//// parse_string("abc", a_followed_by_b_parser)
//// // => Ok(Parsed(["c"], "a"))
//// ```
////
//// The `right` combinator works the same way but ignores the result of the second parser.
////
//// ```gleam
//// let b_preceeded_by_a_parser = right(just("a"), just("b"))
//// parse_string("abc", b_preceeded_by_a_parser)
//// // => Ok(Parsed(["c"], "b"))
//// ```
////
//// These building blocks are enough to build many combinators that can parse complex data structures.
//// For example the `sep_by0` and `sep_by1` combinators which can be used to parse lists of items
//// separated by a delimiter.
////
//// ```
//// let comma_separated_letters = sep_by0(a_or_b_or_c_parser, just(","))
//// parse_string("a,b,c", comma_separated_letters)
//// // => Ok(Parsed([], ["a", "b", "c"]))
//// ```
////
//// ### Transforming the results
////
//// The `map` combinator can be used to transform the result of a parser.
//// It takes a parser and a function that takes the result of the parser and returns a new value.
////
//// Let's say we want to parse our abc letters and transform them into the following types:
////
//// ```gleam
//// type Letter {
////   A
////   B
////   C
////   Other(String)
//// }
////
//// type Letters {
////   Letters(List(Letter))
//// }
//// ```
////
//// First we need to define parsers for each letter:
////
//// ```gleam
//// let a_parser = map(just("a"), fn(_letter) { Letter.A })
//// let b_parser = map(just("b"), fn(_letter) { Letter.B })
//// let c_parser = map(just("c"), fn(_letter) { Letter.C })
//// ```
////
//// In our map function we ignore the input and return the corresponding letter. We will get to the `Other` case later.
////
//// Now that we have parsers that take a char and we can combine them as previously and then use the `map` combinator
//// to transform the result into `Letters`:
////
//// ```gleam
//// let letters_parser =
////   choice([a_parser, b_parser, c_parser])
////   |> map(Letters)
////
//// parse_string("abc", letters_parser)
//// // => Ok(Parsed([], Letters([Letter.A, Letter.B, Letter.C])))
//// ```
////
//// Let's add the `Other` case to our parser, for that we can use the satisfying combinator which takes a function
//// that returns a boolean indicating if the input matches or not. We can use it to check if the input is a letter
//// of the alphabet.
////
//// While we are at it, let's also use `to` instead of `map` to transform our a, b, and c parsers into the `Letter` type.
//// `to` is a shorthand for `map` where you want to ignore the input and just return a new value.
////
//// ```gleam
//// let a_parser = to(just("a"), Letter.A)
//// let b_parser = to(just("b"), Letter.B)
//// let c_parser = to(just("c"), Letter.C)
//// let other_parser = satisfying(fn(char) { is_alphabetic(char) })
////
//// let letters_parser =
////  choice([a_parser, b_parser, c_parser, other_parser])
////  |> map(Letters)
////
//// parse_string("abcd", letters_parser)
//// // => Ok(Parsed(["d"], Letters([Letter.A, Letter.B, Letter.C, Letter.Other("d")]))
//// ```
////
//// ### More examples
////
//// Please have a look at the tests for more complex examples, such as parsing JSON or Brainf*ck.

import gleam/string
import pears/input.{type Input}

/// Returned by a parser when it is successful. It contains the remaining input and the parsed value.
pub type Parsed(i, a) {
  Parsed(input: Input(i), value: a)
}

pub type ParseError(i) {
  ParseError(input: Input(i), expected: List(String))
}

/// The result of a parser. It is either a `Parsed` or a `ParseError`.
pub type ParseResult(i, a) =
  Result(Parsed(i, a), ParseError(i))

/// The generic parser type. It's an alias for a function that takes an `Input(i)` and returns a `ParseResult(i, a)`.
pub type Parser(i, a) =
  fn(Input(i)) -> ParseResult(i, a)

/// Helper function that takes a parser and an input and runs the parser on the input.
pub fn parse(i: List(i), p: Parser(i, a)) -> ParseResult(i, a) {
  p(i)
}

/// Helper function that takes a string and a parser and runs the parser on the string.
pub fn parse_string(i: String, p: Parser(String, a)) -> ParseResult(String, a) {
  i
  |> string.to_graphemes()
  |> parse(p)
}

pub fn ok(input: Input(i), value: a) -> ParseResult(i, a) {
  Ok(Parsed(input, value))
}
