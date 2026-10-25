import gleedoc
import gleeunit

pub fn main() {
  gleedoc.default() |> gleedoc.run_with(gleeunit.main)
}
