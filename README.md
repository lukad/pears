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
import pears.{type Parser, Parsed}
import pears/chars.{type Char, number}
import pears/combinators.{alt, between, just, lazy, map, sep_by0}

pub type Tree(a) {
  Leaf(a)
  Node(List(Tree(a)))
}

fn tree_parser(p: Parser(Char, a)) -> Parser(Char, Tree(a)) {
  let tree = lazy(fn() { tree_parser(p) })
  let leaf = map(p, Leaf)
  let node =
    tree
    |> sep_by0(just(","))
    |> between(just("["), just("]"))
    |> map(Node)
  alt(leaf, node)
}

pub fn main() {
  let parse_result =
    "[1,[2,3],4]"
    |> chars.input()
    |> tree_parser(number())

  let assert Ok(Parsed([], Node([Leaf(1), Node([Leaf(2), Leaf(3)]), Leaf(4)]))) =
    parse_result
}
```

Further documentation can be found at [https://hexdocs.pm/pears](https://hexdocs.pm/pears/pears.html).

See the [test](./test) directory for more examples.

## What's missing?

- Proper error handling
- Test helpers
- ...

## Development

```sh
gleam test  # Run the tests
gleam shell # Run an Erlang shell
```
