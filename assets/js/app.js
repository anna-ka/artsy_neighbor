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
import {hooks as colocatedHooks} from "phoenix-colocated/artsy_neighbor"
import topbar from "../vendor/topbar"

const ScrollToBottom = {
  mounted()  { this.scrollToBottom() },
  updated()  { this.scrollToBottom() },
  scrollToBottom() { this.el.scrollTop = this.el.scrollHeight }
}

const CategoryScroll = {
  mounted() {
    const inner = this.el.querySelector("[data-scroll-inner]")
    this.el.querySelectorAll("[data-scroll-dir]").forEach(btn => {
      btn.addEventListener("click", () => {
        inner.scrollBy({ left: parseInt(btn.dataset.scrollDir) * 200, behavior: "smooth" })
      })
    })
  }
}

// Asking before a dangerous action, in our own box instead of the
// browser's plain "OK / Cancel" pop-up. Any clickable element with
// data-confirm gets it:
//
//   data-confirm         the question, shown as the heading (required)
//                        e.g. "Delete “Crow at Ross Bay”?"
//   data-confirm-detail  a sentence or two on what will happen (optional)
//   data-confirm-yes     words on the "yes" button (default "Yes, delete")
//   data-confirm-kind    "ordinary" for actions that are not dangerous,
//                        such as restoring: the "yes" button is then
//                        the main dark button instead of solid red
//
// How it works: phoenix_html (imported above) sends a
// "phoenix.link.click" event to the clicked element before anything else
// happens, and cancelling that event cancels the click. We listen first
// (the `true` below), stop the click, and open the box. If "yes" is
// chosen, we mark the element and click it again; the second time we let
// the click through. Stopping the event also keeps phoenix_html's own
// pop-up from appearing.
const confirmDialog = document.getElementById("confirm-dialog")

window.addEventListener("phoenix.link.click", event => {
  const element = event.target
  const question = element.getAttribute("data-confirm")
  if (!question || !confirmDialog) return

  event.stopPropagation()

  if (element.dataset.confirmed === "yes") {
    delete element.dataset.confirmed
    return
  }

  event.preventDefault()
  askToConfirm(element, question)
}, true)

function askToConfirm(element, question) {
  const detail = element.getAttribute("data-confirm-detail") || ""
  const yesWords = element.getAttribute("data-confirm-yes") || "Yes, delete"
  const ordinary = element.getAttribute("data-confirm-kind") === "ordinary"

  // textContent, not innerHTML: the words may contain a title typed by a
  // user, and must show as plain text.
  document.getElementById("confirm-title").textContent = question
  const detailEl = document.getElementById("confirm-detail")
  detailEl.textContent = detail
  detailEl.hidden = detail === ""

  const yesButton = document.getElementById("confirm-yes")
  yesButton.textContent = yesWords
  yesButton.classList.toggle("btn-danger-final", !ordinary)
  yesButton.classList.toggle("btn-main", ordinary)

  // The buttons sit in a <form method="dialog">, so pressing one closes
  // the box and leaves its value ("yes" / "no") in returnValue. Esc
  // closes it without a value.
  confirmDialog.returnValue = ""
  confirmDialog.addEventListener("close", () => {
    if (confirmDialog.returnValue === "yes") {
      element.dataset.confirmed = "yes"
      element.click()
    }
  }, {once: true})

  confirmDialog.showModal()
}

// Placeholders: features shown but not built yet (<.placeholder> in
// custom_components.ex). Pressing anything inside one shows a small note,
// "Not built yet: <what>", just below it, and does nothing else.
//
// How it works: we listen for clicks on the whole window, in the
// "capture" phase (the `true` below), which runs before LiveView and the
// browser itself handle the click. For a click inside a placeholder we
// cancel it (so a link goes nowhere, a button submits nothing) and show
// the note. The next click anywhere else, or Esc, hides it again.
const placeholderNote = document.getElementById("placeholder-note")

window.addEventListener("click", event => {
  if (!placeholderNote) return
  const placeholder = event.target.closest("[data-placeholder]")

  if (!placeholder) {
    placeholderNote.hidden = true
    return
  }

  event.preventDefault()
  event.stopPropagation()
  showPlaceholderNote(event.target, placeholder.getAttribute("data-placeholder"))
}, true)

window.addEventListener("keydown", event => {
  if (event.key === "Escape" && placeholderNote) placeholderNote.hidden = true
})

function showPlaceholderNote(pressed, what) {
  // The wrapper itself takes no space on the page, so we place the note
  // under the element that was actually pressed (its button or link, if
  // the click landed on, say, an icon inside one).
  const element = pressed.closest("button, a") || pressed
  const box = element.getBoundingClientRect()

  // textContent: shown as plain text, never as markup.
  placeholderNote.textContent = `Not built yet: ${what}`
  placeholderNote.hidden = false

  // Page coordinates (window position + how far the page is scrolled),
  // kept inside the window on the right.
  const noteWidth = placeholderNote.offsetWidth
  const rightmost = window.scrollX + document.documentElement.clientWidth - noteWidth - 16
  placeholderNote.style.left = `${Math.max(16, Math.min(window.scrollX + box.left, rightmost))}px`
  placeholderNote.style.top = `${window.scrollY + box.bottom + 6}px`
}

const csrfToken =document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, CategoryScroll, ScrollToBottom},
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

