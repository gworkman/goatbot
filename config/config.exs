# This file is responsible for configuring your application and its
# dependencies.
#
# This configuration file is loaded before any dependency and is restricted to
# this project.
import Config
config :bb_nsk, name: "goatbot"

# The phone controller, `GoatbotWeb.ControllerLive`. Its JS (and the CSS it
# imports) is bundled by esbuild into priv/static/assets.
config :esbuild,
  version: "0.25.4",
  goatbot: [
    args: ~w(js/app.js --bundle --target=es2020 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :phoenix, json_library: Jason

config :goatbot, GoatbotWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: GoatbotWeb.ErrorHTML], layout: false],
  pubsub_server: Goatbot.PubSub,
  live_view: [signing_salt: "c9Kq2v7T"]

# Breeze (the `Goatbot.Dashboard` TUI) sizes its render cache from :os_mon when
# it's running. It isn't here, so give it a fixed budget that suits the board.
config :back_breeze, render_cache_max_memory_bytes: 16 * 1_024 * 1_024

# Enable the Nerves integration with Mix
Application.start(:nerves_bootstrap)

# Customize non-Elixir parts of the firmware. See
# https://nerves.hexdocs.pm/advanced-configuration.html for details.

config :nerves, :firmware,
  rootfs_overlay: "rootfs_overlay",
  provisioning: "config/provisioning.conf"

# Set the SOURCE_DATE_EPOCH date for reproducible builds.
# See https://reproducible-builds.org/docs/source-date-epoch/ for more information

config :nerves, source_date_epoch: "1791461140"

if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end
