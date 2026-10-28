export const ProductTour = {
  mounted() {
    this.steps = JSON.parse(this.el.dataset.tourSteps)
    this.index = 0
    this.activeTarget = null
    this.dismiss = () => this.finish()
    this.next = () => this.index === this.steps.length - 1 ? this.finish() : this.show(this.index + 1)
    this.back = () => this.show(this.index - 1)
    this.reposition = () => this.positionCard()
    this.keydown = event => {
      if (event.key === "Escape") this.finish()
      if (event.key === "ArrowRight") this.next()
      if (event.key === "ArrowLeft" && this.index > 0) this.back()
    }

    this.el.querySelectorAll("[data-tour-dismiss]").forEach(button => button.addEventListener("click", this.dismiss))
    this.el.querySelector("[data-tour-next]").addEventListener("click", this.next)
    this.el.querySelector("[data-tour-back]").addEventListener("click", this.back)
    window.addEventListener("keydown", this.keydown)
    window.addEventListener("resize", this.reposition)

    if (this.el.dataset.autoStart === "true") {
      this.show(0)
      const url = new URL(window.location.href)
      url.searchParams.delete("tour")
      window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`)
    }
  },

  show(index) {
    this.clearTarget()
    this.index = Math.max(0, Math.min(index, this.steps.length - 1))
    const step = this.steps[this.index]
    document.getElementById("sidebar-shell")?.classList.add("sidebar-mobile-open")
    document.getElementById("sidebar-aside")?.classList.remove("sidebar-collapsed")

    this.activeTarget = document.querySelector(step.selector)
    if (this.activeTarget) {
      this.activeTarget.dataset.tourPreviousStyle = this.activeTarget.getAttribute("style") || ""
      this.activeTarget.style.position = "relative"
      this.activeTarget.style.zIndex = "55"
      this.activeTarget.style.boxShadow = "0 0 0 4px rgba(211, 239, 74, 0.9), 0 12px 30px rgba(0, 0, 0, 0.25)"
      this.activeTarget.scrollIntoView({block: "nearest"})
    }

    this.el.querySelector("[data-tour-progress]").textContent = `Quick tour · ${this.index + 1} of ${this.steps.length}`
    this.el.querySelector("[data-tour-title]").textContent = step.title
    this.el.querySelector("[data-tour-description]").textContent = step.description
    this.el.querySelector("[data-tour-back]").disabled = this.index === 0
    this.el.querySelector("[data-tour-next]").textContent = this.index === this.steps.length - 1 ? "Finish" : "Next"
    this.el.classList.remove("hidden")
    this.positionCard()
    window.clearTimeout(this.positionTimer)
    this.positionTimer = window.setTimeout(() => this.positionCard(), 220)
    this.el.querySelector("[data-tour-next]").focus()
  },

  positionCard() {
    const card = this.el.querySelector("[data-tour-card]")
    const arrow = this.el.querySelector("[data-tour-arrow]")
    if (!card || !this.activeTarget) return

    const target = this.activeTarget.getBoundingClientRect()
    const gap = 20
    const edge = 16
    const roomOnRight = window.innerWidth - target.right - gap

    if (window.innerWidth >= 640 && roomOnRight >= card.offsetWidth + edge) {
      const top = Math.min(
        Math.max(target.top + target.height / 2 - card.offsetHeight / 2, edge),
        window.innerHeight - card.offsetHeight - edge
      )
      card.style.left = `${target.right + gap}px`
      card.style.top = `${top}px`
      arrow.classList.remove("hidden")
      arrow.style.top = `${Math.min(Math.max(target.top + target.height / 2 - top, 24), card.offsetHeight - 24)}px`
    } else {
      card.style.left = `${Math.max((window.innerWidth - card.offsetWidth) / 2, edge)}px`
      card.style.top = `${Math.max(window.innerHeight - card.offsetHeight - edge, edge)}px`
      arrow.classList.add("hidden")
    }
  },

  clearTarget() {
    if (!this.activeTarget) return
    this.activeTarget.setAttribute("style", this.activeTarget.dataset.tourPreviousStyle || "")
    delete this.activeTarget.dataset.tourPreviousStyle
    this.activeTarget = null
  },

  finish() {
    this.clearTarget()
    this.el.classList.add("hidden")
    localStorage.setItem(this.el.dataset.tourKey, "complete")
    document.getElementById("sidebar-shell")?.classList.remove("sidebar-mobile-open")
  },

  destroyed() {
    this.clearTarget()
    window.clearTimeout(this.positionTimer)
    window.removeEventListener("keydown", this.keydown)
    window.removeEventListener("resize", this.reposition)
  }
}
