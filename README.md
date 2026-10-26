# Pears - A parser combinator library for Gleam

[![Package Version](https://img.shields.io/hexpm/v/pears)](https://hex.pm/packages/pears)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/pears/)

🚧️ **This library is in early development. Expect breaking changes.** 🚧

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

Further documentation can be found at [https://hexdocs.pm/pears](https://hexdocs.pm/pears/pears.html).

See the [test](./test) directory for more examples.

## What's missing?

- Test helpers
- ...

## Development

```sh
gleam test               # Run the tests, including doc examples (via gleedoc)
gleam run -m pears_bench # Run the benchmarks
gleam shell              # Run an Erlang shell
```

Add `--target javascript` to run the tests or benchmarks on JavaScript.
