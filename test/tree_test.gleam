import gleam/string
import gleeunit/should
import pears.{type ParseResult, type Parser, Parsed}
import pears/chars.{type Char, number, string}
import pears/combinators.{alt, between, eof, just, lazy, left, map, sep_by0}

pub type Tree(a) {
  Leaf(a)
  Node(List(Tree(a)))
}

fn tree_parser() -> Parser(Char, Tree(Int)) {
  let tree = lazy(tree_parser)
  let leaf = map(number(), Leaf)
  let node =
    tree
    |> sep_by0(just(","))
    |> between(just("["), just("]"))
    |> map(Node)
  alt(leaf, node)
}

fn parse(input: String) -> ParseResult(Char, Tree(Int)) {
  input
  |> string.to_graphemes()
  |> left(tree_parser(), eof())
}

pub fn parse_tree_test() {
  "1"
  |> parse()
  |> should.equal(Ok(Parsed([], Leaf(1))))

  "[1,2,3]"
  |> parse()
  |> should.equal(Ok(Parsed([], Node([Leaf(1), Leaf(2), Leaf(3)]))))

  "[1,[2,3],4]"
  |> parse()
  |> should.equal(
    Ok(Parsed([], Node([Leaf(1), Node([Leaf(2), Leaf(3)]), Leaf(4)]))),
  )

  "[]"
  |> parse()
  |> should.equal(Ok(Parsed([], Node([]))))
}
