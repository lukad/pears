//// Parses statements like `let x = 1 + 2 * y` in two steps: a lexer turns the
//// source into tokens, then a parser over those tokens builds the AST.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import pears.{type Parser, type Span, Span}
import pears/chars.{type Char}
import pears/combinators.{
  between, chainl1, choice, just, labelled, lazy, many0, map, pair, recognize,
  right, satisfying, succeed, then, to, with_span,
}

pub type Token {
  Let
  Identifier(String)
  Number(Int)
  Equals
  Plus
  Star
  LParen
  RParen
}

pub type Expr {
  Num(Int)
  Var(String)
  Add(Expr, Expr)
  Mul(Expr, Expr)
}

pub type Statement {
  Statement(name: String, value: Expr)
}

// Lexer: characters to tokens, each with the span of characters it came from

fn lexer() -> Parser(Char, List(#(Token, Span))) {
  let word =
    recognize(pair(chars.letter(), many0(chars.alphanumeric())))
    |> map(fn(chars) {
      case string.concat(chars) {
        "let" -> Let
        name -> Identifier(name)
      }
    })

  let token =
    choice([
      word,
      map(chars.number(), Number),
      to(chars.char("="), Equals),
      to(chars.char("+"), Plus),
      to(chars.char("*"), Star),
      to(chars.char("("), LParen),
      to(chars.char(")"), RParen),
    ])
    |> labelled("token")

  right(chars.whitespace0(), many0(chars.lexeme(with_span(token))))
}

// Parser: tokens to AST

/// Parses a token that `f` turns into `Ok(value)`.
fn match_token(
  label: String,
  f: fn(Token) -> Result(a, Nil),
) -> Parser(Token, a) {
  {
    use token <- then(satisfying(fn(token) { result.is_ok(f(token)) }))
    let assert Ok(value) = f(token)
    succeed(value)
  }
  |> labelled(label)
}

fn identifier() -> Parser(Token, String) {
  use token <- match_token("identifier")
  case token {
    Identifier(name) -> Ok(name)
    _ -> Error(Nil)
  }
}

fn number() -> Parser(Token, Int) {
  use token <- match_token("number")
  case token {
    Number(value) -> Ok(value)
    _ -> Error(Nil)
  }
}

fn expression() -> Parser(Token, Expr) {
  let atom =
    choice([
      map(number(), Num),
      map(identifier(), Var),
      between(lazy(expression), just(LParen), just(RParen)),
    ])
  let term = chainl1(atom, to(just(Star), Mul))
  chainl1(term, to(just(Plus), Add))
}

fn statement() -> Parser(Token, Statement) {
  use _ <- then(just(Let))
  use name <- then(identifier())
  use _ <- then(just(Equals))
  use value <- then(expression())
  succeed(Statement(name, value))
}

fn parse(source: String) -> Result(Statement, String) {
  use tokens <- result.try(
    pears.parse_string_all(source, lexer())
    |> result.map_error(chars.format_error(_, source)),
  )

  pears.parse_all(list.map(tokens, fn(token) { token.0 }), statement())
  |> result.map_error(fn(error) {
    // Error positions count tokens, so look up where the token starts in the source.
    let offset = case list.drop(tokens, error.position) {
      [#(_, span), ..] -> span.start
      [] -> string.length(source)
    }
    let #(line, column) = chars.line_column(source, offset)
    "line "
    <> int.to_string(line)
    <> ", column "
    <> int.to_string(column)
    <> ": "
    <> pears.error_message(error)
  })
}

pub fn lexer_test() {
  pears.parse_string_all("let x1 = (2)", lexer())
  |> should.equal(
    Ok([
      #(Let, Span(0, 3)),
      #(Identifier("x1"), Span(4, 6)),
      #(Equals, Span(7, 8)),
      #(LParen, Span(9, 10)),
      #(Number(2), Span(10, 11)),
      #(RParen, Span(11, 12)),
    ]),
  )
}

pub fn parse_test() {
  parse("let x = 1 + 2 * y")
  |> should.equal(Ok(Statement("x", Add(Num(1), Mul(Num(2), Var("y"))))))

  parse("let y = (1 + 2) * 3")
  |> should.equal(Ok(Statement("y", Mul(Add(Num(1), Num(2)), Num(3)))))
}

pub fn lexer_error_test() {
  parse("let x = 1 $ 2")
  |> should.equal(Error(
    "line 1, column 11: expected token or end of input, found \"$\"",
  ))
}

pub fn parser_error_test() {
  parse("let = 1")
  |> should.equal(Error("line 1, column 5: expected identifier, found Equals"))

  parse("let x = 1 +")
  |> should.equal(Error(
    "line 1, column 12: expected number, identifier or LParen, found end of input",
  ))
}
