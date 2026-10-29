# Changelog

## v1.0.0 - 2026-10-29

### Breaking changes

- `gleam_stdlib` 1.x is now required.
- `Parser` is now an opaque type instead of a function. `ParseResult` is removed;
  `parse` and `parse_string` return `Result(Parsed(i, a), ParseError(i))`.
- `Input` is now opaque. Use `input.tokens`, `input.position` and
  `input.at_end`; `get`, `get_n`, `next` and `next_n` are removed.
- `Parsed.input` is renamed to `Parsed.remaining`.
- `ParseError` variants hold the error `position` instead of the remaining
  input, and there is a new `Custom` variant for custom error messages.
- Renamed combinators:
  - `alt` → `or`
  - `just` → `token`
  - `to` → `replace`
  - `left` → `then_skip`
  - `right` → `skip_then`
  - `maybe` → `optional`
  - `labelled` → `label`
- `satisfying` takes a `fn(i) -> Bool`; the `Predicate` type is removed.
- `do_choice` and `pears.ok` are no longer public.
- `chars.number` is renamed to `chars.natural`.
- `chars.char` is removed, use `combinators.token`.
- `chars.input` is removed, use `pears.parse_string`.

### Added

- `pears.parse_all` and `pears.parse_string_all`, which fail if any input is
  left over.
- `pears.format_error`, `pears.error_message`, `chars.format_error` and
  `chars.line_column` for turning errors into messages.
- `succeed`, `fail`, `then` (works well with `use`) and `try_map`.
- `chain_left` and `chain_right` for operator expressions.
- `peek`, `not_followed_by` and `hidden`.
- `exactly`, `at_least`, `at_most`, `many_till`, `sep_end_by0` and
  `sep_end_by1`.
- `with_span` and the `Span` type.
- `chars.letter`, `chars.alphanumeric`, `chars.hex_digit`, `chars.integer`,
  `chars.float`, `chars.string_literal`, `chars.case_insensitive`,
  `chars.lexeme` and `chars.line_comment`.

### Changed

- Errors report the failure that got furthest into the input, and alternatives
  that fail at the same position have their expected tokens merged. Errors from
  `many0`, `optional`, `sep_by0` and similar combinators are kept, so the final
  error says what else could have come next.
- `chars.string` errors point at the first character that doesn't match.
- `label` only relabels errors at the position where its parser started.

### Fixed

- Reading the next token is O(1) instead of O(n).
- `many0` no longer overflows the stack on JavaScript for long inputs and no
  longer loops forever on parsers that succeed without consuming input.
