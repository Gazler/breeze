# Used by "mix format"
locals_without_parens = [attr: 2, attr: 3, slot: 1, slot: 2]

[
  plugins: [Breeze.HTMLFormatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test,examples}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]
