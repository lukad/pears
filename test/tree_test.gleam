import pears.{type Parser}
import pears/chars.{type Char, number}
import pears/combinators.{alt, between, eof, just, lazy, left, map, sep_by0}
import helpers.{should_parse}

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

fn parser() -> Parser(Char, Tree(Int)) {
  left(tree_parser(), eof())
}

pub fn parse_tree_test() {
  parser()
  |> should_parse("1", Leaf(1))
  |> should_parse("[1,2,3]", Node([Leaf(1), Leaf(2), Leaf(3)]))
  |> should_parse(
    "[1,[2,3],4]",
    Node([Leaf(1), Node([Leaf(2), Leaf(3)]), Leaf(4)]),
  )
  |> should_parse("[]", Node([]))
}
