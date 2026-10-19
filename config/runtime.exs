import Config

Application.ensure_all_started(:logger_backends)
LoggerBackends.add(RingLogger)

# On the robot the controller page is served on port 80, from boot: there is no
# `mix phx.server` on a device. `check_origin` is off because the robot is
# reached by whatever address it has on the network that day.
if config_target() != :host do
  config :goatbot, GoatbotWeb.Endpoint,
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 80],
    server: true,
    check_origin: false,
    # A fresh one each boot, so no secret lives in the repository. It only
    # signs the LiveView session, which costs a reconnect after a reboot.
    secret_key_base: Base.encode64(:crypto.strong_rand_bytes(48))
end
