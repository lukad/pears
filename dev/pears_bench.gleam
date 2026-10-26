//// Benchmarks for pears using gleamy_bench.
////
//// ```sh
//// gleam run -m pears_bench
//// gleam run -m pears_bench --target javascript
//// ```

import gleam/io
import gleam/list
import gleam/string
import gleamy/bench
import pears.{type Parser, parse_string}
import pears/chars.{type Char, natural}
import pears/combinators.{
  between, eof, lazy, many0, map, or, sep_by0, then_skip, token,
}

pub type Tree {
  Leaf(Int)
  Node(List(Tree))
}

pub fn main() {
  bench.run(
    [
      bench.Input("1k chars", 1000),
      bench.Input("10k chars", 10_000),
      bench.Input("100k chars", 100_000),
    ],
    [
      parser_bench("many0(token)", many0(token("a")), fn(size) {
        string.repeat("a", size)
      }),
      parser_bench("sep_by0(number)", sep_by0(natural(), token(",")), fn(size) {
        list.repeat("12345", size / 6)
        |> string.join(",")
      }),
      parser_bench("chars.string", keywords(), fn(size) {
        string.repeat("foobar", size / 6)
      }),
      parser_bench("tree (recursive)", tree(), fn(size) {
        let trees =
          list.repeat("[1,[2,3],4]", size / 12)
          |> string.join(",")
        "[" <> trees <> "]"
      }),
    ],
    [],
  )
  |> bench.table([bench.IPS, bench.Min, bench.Mean, bench.P(99)])
  |> io.println()
}

/// Benchmarks `parser` on an input of roughly `size` characters built by
/// `make_input`. The input is built, and checked to be fully consumed by the
/// parser, before timing starts.
fn parser_bench(
  label: String,
  parser: Parser(Char, a),
  make_input: fn(Int) -> String,
) -> bench.Function(Int, Nil) {
  let parser = then_skip(parser, eof())
  bench.SetupFunction(label, fn(size) {
    let input = make_input(size)
    let assert Ok(_) = parse_string(input, parser)
    fn(_) {
      let _ = parse_string(input, parser)
      Nil
    }
  })
}

fn keywords() -> Parser(Char, List(String)) {
  many0(or(chars.string("foo"), chars.string("bar")))
}

fn tree() -> Parser(Char, Tree) {
  let leaf = map(natural(), Leaf)
  let node =
    lazy(tree)
    |> sep_by0(token(","))
    |> between(token("["), token("]"))
    |> map(Node)
  or(leaf, node)
}
