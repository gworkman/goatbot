defmodule GoatbotWeb do
  @moduledoc """
  The robot's web interface: one LiveView, `GoatbotWeb.ControllerLive`, a phone
  controller in place of the badge.

      use GoatbotWeb, :live_view
  """

  def static_paths, do: ~w(assets)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller, only: [get_csrf_token: 0]

      unquote(html_helpers())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: GoatbotWeb.Endpoint,
        router: GoatbotWeb.Router,
        statics: GoatbotWeb.static_paths()
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML

      alias Phoenix.LiveView.JS

      unquote(verified_routes())
    end
  end

  @doc """
  When used, dispatch to the appropriate live_view/html/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
