// An analog stick: drag the knob away from the centre to drive, let go and it
// springs back and the robot stops.
//
// x is right and y is down, each -1 to 1, measured from the centre of the base
// against its radius and clamped to the circle, so diagonals don't reach past
// full deflection. The server turns them into a throttle and a turn.
//
// The position is resent every INTERVAL ms while the stick is held, not only
// when it moves. The robot forgets a drive request after 300 ms, so a thumb
// holding the stick still has to keep saying so, and anything that stops this
// page sending (a backgrounded tab, a closed browser, a dropped connection)
// stops the robot.
export const Stick = {
  INTERVAL: 50,

  mounted() {
    this.knob = this.el.querySelector(".stick-knob")
    this.pointer = null
    this.x = 0
    this.y = 0

    this.el.addEventListener("pointerdown", event => {
      if (this.pointer !== null) return

      this.pointer = event.pointerId
      this.el.setPointerCapture(event.pointerId)
      this.knob.classList.add("held")
      this.move(event)
      this.send()
      this.timer = setInterval(() => this.send(), this.INTERVAL)
    })

    this.el.addEventListener("pointermove", event => {
      if (event.pointerId === this.pointer) this.move(event)
    })

    for (const name of ["pointerup", "pointercancel", "lostpointercapture"]) {
      this.el.addEventListener(name, event => {
        if (event.pointerId === this.pointer) this.release()
      })
    }

    this.onHidden = () => document.hidden && this.release()
    document.addEventListener("visibilitychange", this.onHidden)
  },

  destroyed() {
    document.removeEventListener("visibilitychange", this.onHidden)
    this.release()
  },

  move(event) {
    const rect = this.el.getBoundingClientRect()
    const radius = Math.max(1, rect.width / 2)
    let dx = (event.clientX - (rect.left + rect.width / 2)) / radius
    let dy = (event.clientY - (rect.top + rect.height / 2)) / radius

    const length = Math.hypot(dx, dy)
    if (length > 1) {
      dx /= length
      dy /= length
    }

    this.x = dx
    this.y = dy
    this.place(dx, dy)
  },

  send() {
    this.pushEvent("drive", {x: this.x, y: this.y})
  },

  release() {
    if (this.pointer === null) return

    this.pointer = null
    clearInterval(this.timer)
    this.x = 0
    this.y = 0
    this.knob.classList.remove("held")
    this.place(0, 0)
    this.pushEvent("release", {})
  },

  // The knob travels to the edge of the base, as a fraction of the base's
  // radius, so it sits on the rim at full deflection.
  place(x, y) {
    const radius = this.el.clientWidth / 2
    this.knob.style.transform = `translate(calc(-50% + ${x * radius}px), calc(-50% + ${y * radius}px))`
  }
}
