defmodule GoatbotWeb.ConnCase do
  @moduledoc """
  For tests that need a connection: the controller page's LiveView tests.
  There is no database, so this is just the conn and the endpoint.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint GoatbotWeb.Endpoint

      use GoatbotWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import GoatbotWeb.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
