defmodule GoatbotWeb.Layouts do
  @moduledoc """
  The root layout: a full-screen page for a phone held in one hand, with zoom
  and the browser's own gestures off so a thumb on the stick drives the robot
  rather than scrolling or zooming the page.
  """
  use GoatbotWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta
          name="viewport"
          content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover"
        />
        <meta name="theme-color" content="#111418" />
        <meta name="mobile-web-app-capable" content="yes" />
        <meta name="apple-mobile-web-app-capable" content="yes" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <.live_title default="Goatbot">{assigns[:page_title]}</.live_title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}>
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
