import "../css/app.css"
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {Stick} from "./stick"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  hooks: {Stick},
  params: {_csrf_token: csrfToken}
})

liveSocket.connect()

// For debugging from the browser console: liveSocket.enableDebug()
window.liveSocket = liveSocket
