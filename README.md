# Pears - A parser combinator library for Gleam

[![Package Version](https://img.shields.io/hexpm/v/pears)](https://hex.pm/packages/pears)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/pears/)

## Installation

```sh
gleam add pears
```

## Usage

```gleam
import pears.{type Parser}
import pears/chars.{type Char, natural}
import pears/combinators.{between, lazy, map, or, sep_by0, token}

pub type Tree(a) {
  Leaf(a)
  Node(List(Tree(a)))
}

fn tree_parser(p: Parser(Char, a)) -> Parser(Char, Tree(a)) {
  let tree = lazy(fn() { tree_parser(p) })
  let leaf = map(p, Leaf)
  let node =
    tree
    |> sep_by0(token(","))
    |> between(token("["), token("]"))
    |> map(Node)
  or(leaf, node)
}

pub fn main() {
  let assert Ok(Node([Leaf(1), Node([Leaf(2), Leaf(3)]), Leaf(4)])) =
    pears.parse_string_all("[1,[2,3],4]", tree_parser(natural()))
}
```

`chars.format_error` turns a `ParseError` into a message:

```gleam
let source = "[1,[2,3],4]x"
let assert Error(error) = pears.parse_string_all(source, tree_parser(natural()))

chars.format_error(error, source)
// => line 1, column 12: expected end of input, found "x"
```

Parsers work on any type of token, so you can split lexing and parsing.
Here a lexer turns a string into tokens and a parser turns those into an AST:

```gleam
import pears.{type Parser}
import pears/chars.{type Char}
import pears/combinators.{
  any, chain_left, choice, many0, map, replace, skip_then, token, try_map,
}

pub type Token {
  Number(Int)
  Plus
}

pub type Expr {
  Literal(Int)
  Add(Expr, Expr)
}

fn lexer() -> Parser(Char, List(Token)) {
  let token = choice([map(chars.natural(), Number), replace(token("+"), Plus)])
  skip_then(chars.whitespace0(), many0(chars.lexeme(token)))
}

fn parser() -> Parser(Token, Expr) {
  let literal =
    try_map(any(), fn(token) {
      case token {
        Number(n) -> Ok(Literal(n))
        _ -> Error("expected a number")
      }
    })
  chain_left(literal, replace(token(Plus), Add))
}

pub fn main() {
  let assert Ok(tokens) = pears.parse_string_all("1 + 2 + 3", lexer())
  let assert Ok(Add(Add(Literal(1), Literal(2)), Literal(3))) =
    pears.parse_all(tokens, parser())
}
```

[`test/lexer_test.gleam`](./test/lexer_test.gleam) has a bigger example that
keeps each token's span to report errors with line and column.

Further documentation can be found at [https://hexdocs.pm/pears](https://hexdocs.pm/pears/pears.html).

See the [test](./test) directory for more examples.

## Development

```sh
gleam test               # Run the tests, including doc examples (via gleedoc)
gleam run -m pears_bench # Run the benchmarks
gleam shell              # Run an Erlang shell
```

Add `--target javascript` to run the tests or benchmarks on JavaScript.
