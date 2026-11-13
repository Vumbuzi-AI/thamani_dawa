// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/thamani_dawa"
import topbar from "../vendor/topbar"
import {GoogleMaps} from "./hooks/google_maps"
import {Chart} from "./hooks/chart_hook"
import {DataMatrix} from "./hooks/datamatrix"
import {SsccBarcode} from "./hooks/sscc_barcode"
import {ScanCapture} from "./hooks/scan_capture"
import {ProductTour} from "./hooks/product_tour"
import {FlashAutoDismiss} from "./hooks/flash_auto_dismiss"
import {QuickSaleReceiptPrint} from "./hooks/quick_sale_receipt_print"
import {ConditionalBatchField} from "./hooks/conditional_batch_field"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, GoogleMaps, Chart, DataMatrix, SsccBarcode, ScanCapture, ProductTour, FlashAutoDismiss, QuickSaleReceiptPrint, ConditionalBatchField},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Public landing-page interactions. They are deliberately scoped so LiveViews
// and other public pages do not inherit any of this page's behavior.
const landingPage = document.querySelector("#landing-page")

if (landingPage) {
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  const metricValues = landingPage.querySelectorAll(".metric-value")

  if (metricValues.length && !reduceMotion) {
    const metrics = landingPage.querySelector("dl")
    const observer = new IntersectionObserver((entries, currentObserver) => {
      if (!entries.some(entry => entry.isIntersecting)) return

      const startedAt = performance.now()
      const duration = 1200
      const tick = now => {
        const progress = Math.min((now - startedAt) / duration, 1)
        const eased = 1 - Math.pow(1 - progress, 3)
        metricValues.forEach(metric => {
          metric.textContent = `${Math.round(Number(metric.dataset.target) * eased)}${metric.dataset.suffix || ""}`
        })
        if (progress < 1) requestAnimationFrame(tick)
      }

      requestAnimationFrame(tick)
      currentObserver.disconnect()
    }, {threshold: 0.55})

    if (metrics) observer.observe(metrics)
  }

  const workflowTabs = [...landingPage.querySelectorAll(".workflow-tab")]
  const activateWorkflow = tab => {
    const workflow = tab.dataset.workflow

    workflowTabs.forEach(item => {
      const active = item === tab
      item.classList.toggle("is-active", active)
      item.classList.toggle("bg-[#cdf06d]", active)
      item.classList.toggle("text-[#082a21]", active)
      item.classList.toggle("text-white/60", !active)
      item.setAttribute("aria-selected", String(active))
      item.tabIndex = active ? 0 : -1
    })

    landingPage.querySelectorAll("[data-panel], [data-copy]").forEach(item => {
      item.classList.toggle("hidden", item.dataset.panel !== workflow && item.dataset.copy !== workflow)
    })
  }

  workflowTabs.forEach((tab, index) => {
    tab.tabIndex = index === 0 ? 0 : -1
    tab.addEventListener("click", () => activateWorkflow(tab))
    tab.addEventListener("keydown", event => {
      if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return
      event.preventDefault()
      const nextIndex =
        event.key === "Home" ? 0 :
          event.key === "End" ? workflowTabs.length - 1 :
            (index + (event.key === "ArrowRight" ? 1 : -1) + workflowTabs.length) % workflowTabs.length
      workflowTabs[nextIndex].focus()
      activateWorkflow(workflowTabs[nextIndex])
    })
  })

  const resultButtons = [...landingPage.querySelectorAll(".result-button")]
  resultButtons.forEach(button => {
    button.addEventListener("click", () => {
      const result = button.dataset.result
      resultButtons.forEach(item => {
        const active = item === button
        item.classList.toggle("is-active", active)
        item.classList.toggle("bg-white/60", active)
        item.classList.toggle("px-3.5", active)
        item.setAttribute("aria-pressed", String(active))
      })
      landingPage.querySelectorAll("[data-result-panel]").forEach(panel => {
        panel.classList.toggle("hidden", panel.dataset.resultPanel !== result)
      })
    })
  })
}

const exportedLanding = document.querySelector(".site-header")

if (exportedLanding) {
  const syncHeader = () => exportedLanding.classList.toggle("is-scrolled", window.scrollY > 24)
  syncHeader()
  window.addEventListener("scroll", syncHeader, {passive: true})

  const revealObserver = new IntersectionObserver((entries, observer) => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return
      entry.target.classList.add("is-visible")
      observer.unobserve(entry.target)
    })
  }, {threshold: 0.12})

  document.querySelectorAll(".reveal").forEach(node => revealObserver.observe(node))

  const metricValues = document.querySelectorAll(".metric-value")
  if (metricValues.length) {
    const completeMetrics = () => metricValues.forEach(metric => {
      metric.textContent = `${metric.dataset.target}${metric.dataset.suffix || ""}`
    })

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      completeMetrics()
    } else {
      const metricsObserver = new IntersectionObserver((entries, observer) => {
        if (!entries.some(entry => entry.isIntersecting)) return
        const startedAt = performance.now()
        const tick = now => {
          const progress = Math.min((now - startedAt) / 1400, 1)
          const eased = 1 - Math.pow(1 - progress, 3)
          metricValues.forEach(metric => {
            metric.textContent = `${Math.round(Number(metric.dataset.target) * eased)}${metric.dataset.suffix || ""}`
          })
          if (progress < 1) requestAnimationFrame(tick)
        }
        requestAnimationFrame(tick)
        observer.disconnect()
      }, {threshold: 0.55})
      metricsObserver.observe(document.querySelector(".hero-metrics"))
    }
  }

  const workflowTabs = [...document.querySelectorAll(".workflow-switcher [role='tab']")]
  const activateWorkflow = tab => {
    const workflow = tab.dataset.workflow
    workflowTabs.forEach(item => {
      const active = item === tab
      item.classList.toggle("is-active", active)
      item.setAttribute("aria-selected", String(active))
      item.tabIndex = active ? 0 : -1
    })
    document.querySelectorAll("[data-panel]").forEach(panel => {
      const active = panel.dataset.panel === workflow
      panel.hidden = !active
      panel.classList.toggle("is-active", active)
    })
    document.querySelectorAll("[data-copy]").forEach(copy => {
      const active = copy.dataset.copy === workflow
      copy.hidden = !active
      copy.classList.toggle("is-active", active)
    })
  }

  workflowTabs.forEach((tab, index) => {
    tab.tabIndex = index === 0 ? 0 : -1
    tab.addEventListener("click", () => activateWorkflow(tab))
  })

  const resultButtons = [...document.querySelectorAll("[data-result]")]
  resultButtons.forEach(button => button.addEventListener("click", () => {
    resultButtons.forEach(item => {
      const active = item === button
      item.classList.toggle("is-active", active)
      item.setAttribute("aria-pressed", String(active))
    })
    document.querySelectorAll("[data-result-panel]").forEach(panel => {
      const active = panel.dataset.resultPanel === button.dataset.result
      panel.hidden = !active
      panel.classList.toggle("is-active", active)
    })
  }))

  const menu = document.querySelector("#mobile-menu")
  const menuButton = document.querySelector(".menu-button")
  const menuClose = document.querySelector(".menu-close")
  if (menu && menuButton && menuClose) {
    const closeMenu = () => {
      menu.close()
      menuButton.setAttribute("aria-expanded", "false")
      menuButton.focus()
    }
    menuButton.addEventListener("click", () => {
      menu.showModal()
      menuButton.setAttribute("aria-expanded", "true")
      menuClose.focus()
    })
    menuClose.addEventListener("click", closeMenu)
    menu.addEventListener("click", event => event.target === menu && closeMenu())
    menu.querySelectorAll("a").forEach(link => link.addEventListener("click", () => {
      menu.close()
      menuButton.setAttribute("aria-expanded", "false")
    }))
  }
}

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

