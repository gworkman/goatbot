defmodule GoatbotWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :goatbot

  @session_options [
    store: :cookie,
    key: "_goatbot_key",
    signing_salt: "p3Lw8uXe",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  plug(Plug.Static,
    at: "/",
    from: :goatbot,
    gzip: true,
    only: GoatbotWeb.static_paths()
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(GoatbotWeb.Router)
end
