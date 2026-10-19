defmodule GoatbotWeb.ErrorHTML do
  @moduledoc """
  Error pages, as plain text: "Not Found" for a 404 and so on.
  """
  use GoatbotWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
