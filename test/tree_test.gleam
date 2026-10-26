import helpers.{should_parse}
import pears.{type Parser}
import pears/chars.{type Char, natural}
import pears/combinators.{between, eof, lazy, map, or, sep_by0, then_skip, token}

pub type Tree(a) {
  Leaf(a)
  Node(List(Tree(a)))
}

fn tree_parser() -> Parser(Char, Tree(Int)) {
  let tree = lazy(tree_parser)
  let leaf = map(natural(), Leaf)
  let node =
    tree
    |> sep_by0(token(","))
    |> between(token("["), token("]"))
    |> map(Node)
  or(leaf, node)
}

fn parser() -> Parser(Char, Tree(Int)) {
  then_skip(tree_parser(), eof())
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
