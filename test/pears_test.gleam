import gleedoc
import gleeunit

pub fn main() {
  // gleedoc re-runs `gleam test` without `--target`, which would run the
  // second pass on Erlang, so doc examples are only tested on Erlang.
  case target() {
    "erlang" -> gleedoc.default() |> gleedoc.run_with(gleeunit.main)
    _ -> gleeunit.main()
  }
}

@external(erlang, "pears_test_ffi", "target")
@external(javascript, "./pears_test_ffi.mjs", "target")
fn target() -> String
