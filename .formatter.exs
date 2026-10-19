# Used by "mix format"
[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,test}/**/*.{ex,exs}",
    "lib/*.ex",
    "lib/goatbot/**/*.{ex,exs}",
    "rootfs_overlay/etc/iex.exs"
  ],
  plugins: [Breeze.HTMLFormatter],
  # LiveView templates, formatted with Phoenix's plugin instead.
  subdirectories: ["lib/goatbot_web"],
  import_deps: [:bb_parameter_store_cubdb, :bb, :bb_nsk, :breeze]
]
