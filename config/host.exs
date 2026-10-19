import Config

# Add configuration that is only needed when running on the host here.

config :nerves_runtime,
  kv_backend:
    {Nerves.Runtime.KVBackend.InMemory,
     contents: %{
       # The KV store on Nerves systems is typically read from UBoot-env, but
       # this allows us to use a pre-populated InMemory store when running on
       # host for development and testing.
       #
       # https://nerves-runtime.hexdocs.pm/readme.html#using-nerves_runtime-in-tests
       # https://nerves-runtime.hexdocs.pm/readme.html#nerves-system-and-firmware-metadata

       "nerves_fw_active" => "a",
       "a.nerves_fw_architecture" => "generic",
       "a.nerves_fw_description" => "N/A",
       "a.nerves_fw_platform" => "host",
       "a.nerves_fw_version" => "0.0.0"
     }}

# `mix phx.server` serves the controller on http://localhost:4000. Tests start
# the endpoint without a server. Development only, so a fixed secret is fine.
config :goatbot, GoatbotWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: "Qd7rN0x2mUe8L5yVbK3tW9pZcH1fJ6sA4gR8nT2vX0kM5qB7wE3yU9iO1lP6aS4d",
  server: false
