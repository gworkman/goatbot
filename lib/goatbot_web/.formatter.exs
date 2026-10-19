# The web layer's `~H` templates are LiveView's, not Breeze's, so they get
# Phoenix's formatter rather than the root's Breeze.HTMLFormatter.
[
  inputs: ["**/*.{ex,exs,heex}"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  import_deps: [:phoenix]
]
