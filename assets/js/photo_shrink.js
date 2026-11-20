// Shrinking big photos in the browser before they are uploaded (photo
// speed step 3c). Plan, with the reasons for every rule below:
// docs/plans/2026-11-19-browser-shrinking-and-early-processing.md.
// The trial page it was tried out with: priv/static/trials/photo-shrink.html.
//
// The PhotoShrink hook sits on the photo picker of every photo form
// (PhotoUploads.photo_picker/1). When the artist picks photos, it
// catches them before LiveView sees them, and for each photo, one
// after another:
//
//   - a JPEG, HEIC or ordinary WebP photo bigger than the server's
//     private copy (4096 px on the long side) is shrunk to that size,
//     as a JPEG with the same name ending in ".jpg"
//     (IMG_6457.HEIC → IMG_6457.jpg);
//   - every other file is uploaded as it is: photos that are small
//     enough already, PNG/TIFF/AVIF, WebP photos with see-through parts
//     or moving pictures, files this browser can't read, files that
//     aren't what their name says, and photos whose shrinking failed
//     or took too long. The server checks them as before;
//   - except: a photo that isn't shrunk and is known to be over the
//     server's limit (52 MP) is refused here, without uploading, since
//     the server would refuse it anyway.
//
// Then it hands the photo to LiveView (this.upload), which uploads it
// as before. While it works, the photo shows "Preparing photo…" in the
// list under the picker. The server is kept informed (event
// "photo_picker_state": still preparing? which photos were refused
// here?), so that a save waits for photos being prepared and doesn't
// quietly leave out a refused one.
//
// This is a shortcut, never a requirement: the server checks and
// processes every photo the same way, shrunk or not. So whenever
// anything goes wrong here, the answer is "upload the original".

const JPEG_QUALITY = 0.92
// An old phone with a huge photo may be very slow: then give up and
// upload the original.
const TIME_LIMIT_MS = 15000
// After giving up, wait at most this much longer for the abandoned
// shrinking to finish before starting on the next photo (see
// prepareAll).
const SETTLE_LIMIT_MS = 30000
// Wait at most this long for LiveView to list a photo we handed it
// (see whenListed).
const LISTED_LIMIT_MS = 10000

// Only these are ever shrunk, and only if the file's first bytes agree
// with its name: so a GIF or BMP (which the server refuses) can't get
// in by being turned into a JPEG here.
const SHRINKABLE_ENDINGS = {
  jpeg: ["jpg", "jpeg"],
  heic: ["heic", "heif"],
  "webp-still": ["webp"]
}

// HEIF "brands" (the file's first box says which it is). AVIF uses the
// same container, but is left alone (plan point 3).
const HEIC_BRANDS = ["heic", "heix", "heim", "heis", "hevc", "hevx", "mif1", "msf1"]
const AVIF_BRANDS = ["avif", "avis"]

// ---- Small helpers ----

function fileEnding(name) {
  const dot = name.lastIndexOf(".")
  if (dot === -1) return ""
  return name.slice(dot + 1).toLowerCase()
}

function jpegName(name) {
  const withoutEnding = name.replace(/\.[^.]+$/, "")
  return withoutEnding + ".jpg"
}

function bytesAsText(bytes, start, end) {
  let text = ""
  for (let i = start; i < end && i < bytes.length; i++) {
    text += String.fromCharCode(bytes[i])
  }
  return text
}

// Waits until the browser has drawn the page once, so that "Preparing
// photo…" shows before the heavy work starts.
function nextPaint() {
  return new Promise(resolve => {
    requestAnimationFrame(() => setTimeout(resolve, 0))
  })
}

function wait(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

// ---- What the file is: read from its first bytes ----

// A WebP file says in its first 30 bytes whether it has see-through
// parts or moving pictures, and how big it is (the "RIFF container"
// layout: https://developers.google.com/speed/webp/docs/riff_container).
function webpHeader(bytes) {
  const firstChunk = bytesAsText(bytes, 12, 16)
  if (firstChunk === "VP8 ") {
    // Simple lossy WebP: can't have see-through parts. It's shrunk if
    // big, so its size is read later from the picture itself.
    return {kind: "webp-still", pixels: null}
  }
  if (firstChunk === "VP8L") {
    // Simple lossless WebP: after a signature byte (byte 20) come 14
    // bits of (width - 1) and 14 of (height - 1), then one bit "alpha
    // is used", which is bit 4 of byte 24.
    const width = 1 + (((bytes[22] & 0x3f) << 8) | bytes[21])
    const height = 1 + (((bytes[24] & 0x0f) << 10) | (bytes[23] << 2) | ((bytes[22] & 0xc0) >> 6))
    const alphaIsUsed = (bytes[24] >> 4) & 1
    return {kind: alphaIsUsed === 1 ? "webp-see-through" : "webp-still", pixels: width * height}
  }
  if (firstChunk === "VP8X") {
    // Extended WebP: byte 20 holds flags (0x10 = has see-through
    // parts, 0x02 = moving); bytes 24–26 and 27–29 are (width - 1) and
    // (height - 1), least significant byte first.
    const flags = bytes[20]
    const width = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16))
    const height = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16))
    let kind = "webp-still"
    if ((flags & 0x10) !== 0) kind = "webp-see-through"
    if ((flags & 0x02) !== 0) kind = "webp-moving"
    return {kind: kind, pixels: width * height}
  }
  return {kind: "other", pixels: null}
}

// HEIC and AVIF files start with an "ftyp" box: its size (bytes 0–3),
// "ftyp", the main brand (bytes 8–11), a version, then more brands.
function heifKind(bytes) {
  const boxSize = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]
  const brands = [bytesAsText(bytes, 8, 12)]
  for (let at = 16; at + 4 <= Math.min(boxSize, bytes.length); at += 4) {
    brands.push(bytesAsText(bytes, at, at + 4))
  }
  if (brands.some(brand => AVIF_BRANDS.includes(brand))) return "avif"
  if (brands.some(brand => HEIC_BRANDS.includes(brand))) return "heic"
  return "other"
}

// Returns {kind, pixels}: kind is "jpeg", "heic", "webp-still",
// "webp-see-through", "webp-moving", "png", "avif" or "other"; pixels is
// the pixel count where the first bytes say it (PNG, most WebP), else
// null.
async function readHeader(file) {
  let bytes
  try {
    bytes = new Uint8Array(await file.slice(0, 64).arrayBuffer())
  } catch (error) {
    return {kind: "other", pixels: null}
  }
  if (bytes.length < 30) return {kind: "other", pixels: null}

  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return {kind: "jpeg", pixels: null}
  }
  if (bytesAsText(bytes, 0, 8) === "\x89PNG\r\n\x1a\n") {
    // The first chunk, IHDR, starts with width and height (bytes 16–23,
    // most significant byte first).
    const view = new DataView(bytes.buffer)
    return {kind: "png", pixels: view.getUint32(16) * view.getUint32(20)}
  }
  if (bytesAsText(bytes, 0, 4) === "RIFF" && bytesAsText(bytes, 8, 12) === "WEBP") {
    return webpHeader(bytes)
  }
  if (bytesAsText(bytes, 4, 8) === "ftyp") {
    return {kind: heifKind(bytes), pixels: null}
  }
  return {kind: "other", pixels: null}
}

// Why a file is uploaded as it is without even trying, or null if it
// may be shrunk.
function leftAloneReason(file, header) {
  const endings = SHRINKABLE_ENDINGS[header.kind]
  if (endings === undefined) {
    if (header.kind === "webp-see-through") return "a WebP with see-through parts"
    if (header.kind === "webp-moving") return "a moving WebP"
    return "not a JPEG, HEIC or ordinary WebP (" + header.kind + ")"
  }
  if (!endings.includes(fileEnding(file.name))) return "its name doesn't match its contents"
  return null
}

// ---- Reading, shrinking, writing ----

// Loads the file into an <img>. Resolves once the browser knows the
// picture's size (many browsers only decode the pixels when drawing).
function loadPicture(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => resolve({img: img, url: url})
    img.onerror = () => {
      URL.revokeObjectURL(url)
      reject(new Error("the browser can't read this file"))
    }
    img.src = url
  })
}

// Lets the browser drop the full-size picture from memory.
function releasePicture(loaded) {
  loaded.img.onload = null
  loaded.img.onerror = null
  loaded.img.removeAttribute("src")
  URL.revokeObjectURL(loaded.url)
}

function canvasToJpeg(canvas) {
  return new Promise(resolve => {
    canvas.toBlob(blob => resolve(blob), "image/jpeg", JPEG_QUALITY)
  })
}

// When a browser runs out of room for a picture, it may draw nothing
// without any error. The photos that get this far have no see-through
// parts (JPEG, HEIC, ordinary WebP), so if nine spots spread over the
// canvas are all see-through, drawing failed.
function looksEmpty(context, width, height) {
  const fractions = [0.1, 0.5, 0.9]
  for (const fx of fractions) {
    for (const fy of fractions) {
      const x = Math.floor(width * fx)
      const y = Math.floor(height * fy)
      const pixel = context.getImageData(x, y, 1, 1).data
      if (pixel[3] !== 0) return false
    }
  }
  return true
}

function original(why) {
  return {kind: "original", why: why}
}

// Shrinks one photo if it should be and can be. Returns
// {kind: "shrunk", file} or {kind: "original", why}. Writes the photo's
// pixel count into `job.pixels` as soon as it's known, so the caller
// still has it if this takes too long. Stops early once `job.stop` is
// set (the caller gave up on it), to free its memory sooner.
async function shrinkPhoto(file, longSideLimit, job) {
  const header = await readHeader(file)
  job.pixels = header.pixels

  // Checked before loading the picture: no need to load a photo that's
  // uploaded as it is anyway.
  const reason = leftAloneReason(file, header)
  if (reason !== null) return original(reason)

  let loaded
  try {
    loaded = await loadPicture(file)
  } catch (error) {
    return original("this browser can't read it")
  }

  const width = loaded.img.naturalWidth
  const height = loaded.img.naturalHeight
  job.pixels = width * height

  const longSide = Math.max(width, height)
  if (longSide <= longSideLimit || job.stop) {
    releasePicture(loaded)
    return original(job.stop ? "stopped" : "small enough already")
  }

  // Draw it smaller on a canvas, then write it as a JPEG. Everything
  // here can fail on a phone short of memory, so all of it is inside
  // the try. Browsers turn the photo upright (its orientation note)
  // when drawing it, and the JPEG carries no metadata (no GPS).
  const scale = longSideLimit / longSide
  const targetWidth = Math.max(1, Math.round(width * scale))
  const targetHeight = Math.max(1, Math.round(height * scale))
  const canvas = document.createElement("canvas")
  let blob

  try {
    canvas.width = targetWidth
    canvas.height = targetHeight
    // The default canvas colours (sRGB): in the trial, Display P3 made
    // no visible difference, and the server converts to sRGB anyway.
    const context = canvas.getContext("2d")
    if (!context) return original("no canvas")
    context.imageSmoothingEnabled = true
    context.imageSmoothingQuality = "high"
    context.drawImage(loaded.img, 0, 0, targetWidth, targetHeight)

    // Some browsers only really draw when pixels are read back, so the
    // empty check counts as part of drawing.
    if (looksEmpty(context, targetWidth, targetHeight)) {
      return original("the drawing came out empty")
    }
    // The full-size picture isn't needed any more.
    releasePicture(loaded)
    if (job.stop) return original("stopped")
    blob = await canvasToJpeg(canvas)
  } catch (error) {
    return original("error while shrinking (" + error.message + ")")
  } finally {
    // (Releasing twice does no harm.)
    releasePicture(loaded)
    // Give the canvas memory back straight away.
    canvas.width = 0
    canvas.height = 0
  }

  if (!blob) return original("couldn't write the JPEG")

  const shrunk = new File([blob], jpegName(file.name), {
    type: "image/jpeg",
    lastModified: file.lastModified
  })
  return {kind: "shrunk", file: shrunk}
}

// Decides what to do with one photo. Returns {send: file} (shrunk or
// the original) or {refuse: true}, plus `settled`: a promise that
// resolves once the shrinking has really finished, which is later than
// the answer if it took too long. Never throws.
async function preparePhoto(file, limits) {
  const start = performance.now()
  const job = {pixels: null, stop: false}
  let timer
  const tooSlow = new Promise(resolve => {
    timer = setTimeout(() => resolve(original("took longer than " + TIME_LIMIT_MS / 1000 + " s")),
                       TIME_LIMIT_MS)
  })

  const shrinking = shrinkPhoto(file, limits.longSide, job)
  // Never rejects, so waiting on it is always safe.
  const settled = shrinking.catch(() => {})

  let outcome
  try {
    // Whichever comes first. If the time limit wins, the shrinking is
    // told to stop, but can't be interrupted in the middle of a step.
    outcome = await Promise.race([shrinking, tooSlow])
  } catch (error) {
    outcome = original("unexpected error (" + error.message + ")")
  } finally {
    clearTimeout(timer)
    job.stop = true
  }

  const ms = Math.round(performance.now() - start)
  const overLimit = job.pixels !== null && job.pixels > limits.maxPixels

  // One line per photo in the browser's console, for checking by hand.
  console.info("PhotoShrink:", file.name, file.type, file.size, "bytes,",
               job.pixels, "pixels →", outcome.kind,
               outcome.kind === "shrunk" ? outcome.file.size + " bytes" : outcome.why,
               overLimit && outcome.kind !== "shrunk" ? "(over the limit: refused)" : "",
               ms, "ms")

  if (outcome.kind === "shrunk") return {send: outcome.file, settled: settled}
  if (overLimit) return {refuse: true, settled: settled}
  return {send: file, settled: settled}
}

// ---- The hook ----

export const PhotoShrink = {
  mounted() {
    this.limits = {
      maxPixels: Number(this.el.dataset.maxPixels),
      longSide: Number(this.el.dataset.longSide)
    }
    this.tooLargeMessage = this.el.dataset.tooLargeMessage
    this.list = this.el.querySelector("[data-preparing-list]")
    // The template leaves a line break inside the list, which keeps
    // its CSS `empty:hidden` from hiding it (and its gap) while it has
    // no rows. LiveView leaves the list alone (phx-update="ignore"), and
    // we only ever add and remove whole rows, so it stays truly empty.
    this.list.replaceChildren()
    // Photos picked but not prepared yet, in the order picked:
    // {file, row, uploadName}.
    this.waiting = []
    this.preparing = false
    // Photos handed to LiveView that it hasn't listed yet (see
    // whenListed): {row, file, finish}.
    this.handedOver = []

    this.catchPick = event => this.picked(event)
    // `true`: listen in the "capture" phase, i.e. before the event
    // reaches the file input and LiveView's own listener on the window.
    this.el.addEventListener("input", this.catchPick, true)
    this.el.addEventListener("change", this.catchPick, true)

    // Watches the picker for LiveView adding its rows.
    this.observer = new MutationObserver(() => this.removeHandedOverRows())
    this.observer.observe(this.el, {childList: true, subtree: true})
  },

  // The picker is gone (e.g. the profile form's Previous button, or
  // leaving the page). Photos still waiting can't be uploaded any more
  // (their upload slot went with the picker), and the refused rows are
  // gone: tell the server, or it would keep refusing to save.
  destroyed() {
    this.gone = true
    this.observer.disconnect()
    for (const item of [...this.handedOver]) item.finish()
    this.waiting = []
    this.preparing = false
    this.tellServer()
  },

  // After a lost connection the server has forgotten what we told it:
  // tell it again.
  reconnected() {
    this.tellServer()
  },

  // Sends the server the current state: are photos being prepared,
  // and the names of the photos refused here whose red rows are still
  // shown. Without a connection the message can't go (pushEvent then
  // fails); reconnected() sends it again once the connection is back.
  tellServer() {
    const refused = []
    if (!this.gone) {
      for (const row of this.list.querySelectorAll("[data-refused]")) {
        refused.push(row.dataset.name)
      }
    }
    try {
      const sent = this.pushEvent("photo_picker_state", {preparing: this.preparing, refused: refused})
      if (sent && sent.catch) sent.catch(() => {})
    } catch (error) {
      // not connected right now
    }
  },

  picked(event) {
    const input = event.target
    if (!(input instanceof HTMLInputElement) || input.type !== "file") return
    // The events LiveView makes itself after this.upload come from
    // code, not from the artist ("not trusted"): let those through.
    if (!event.isTrusted) return

    event.stopPropagation()
    // A pick sends "input" and then "change": the first takes the
    // files, the second finds none left.
    const files = Array.from(input.files || [])
    if (files.length === 0) return
    input.value = ""

    for (const file of files) {
      this.waiting.push({file: file, row: this.addPreparingRow(file.name), uploadName: input.name})
    }
    if (!this.preparing) this.prepareAll()
  },

  // One photo after another, so a phone never holds two big photos in
  // memory at once. Each goes to LiveView as soon as it's ready, so its
  // upload runs while the next one is being shrunk.
  async prepareAll() {
    this.preparing = true
    this.tellServer()

    while (this.waiting.length > 0) {
      const {file, row, uploadName} = this.waiting.shift()
      await nextPaint()
      const result = await preparePhoto(file, this.limits)
      // The artist has left the page or the picker meanwhile.
      if (this.gone) return

      if (result.refuse) {
        this.showRefused(row, file.name)
        this.tellServer()
      } else {
        this.upload(uploadName, [result.send])
        await this.whenListed(row, result.send)
        if (this.gone) return
      }

      // If shrinking was given up for taking too long, it may still be
      // holding the big picture: wait for it (up to a limit) before
      // starting on the next photo.
      await Promise.race([result.settled, wait(SETTLE_LIMIT_MS)])
      if (this.gone) return
    }

    this.preparing = false
    this.tellServer()
  },

  // Resolves once LiveView lists the photo just handed to it (its own
  // row has appeared), or after LISTED_LIMIT_MS at the latest. Our
  // "Preparing photo…" row stays until then, so the photo never
  // disappears from the list in between. And the next photo is handed
  // over only after that: LiveView counts a file as picked only once
  // the server has answered for it, and a file handed over before
  // that answer came back got no preview (found in the browser checks,
  // 2026-11-20).
  whenListed(row, file) {
    return new Promise(resolve => {
      const item = {row: row, file: file, finish: null}
      const timer = setTimeout(() => item.finish(), LISTED_LIMIT_MS)
      item.finish = () => {
        clearTimeout(timer)
        row.remove()
        this.handedOver = this.handedOver.filter(other => other !== item)
        resolve()
      }
      this.handedOver.push(item)
      this.removeHandedOverRows()
    })
  },

  // Finishes waiting for the handed-over photos whose LiveView row is
  // there now. LiveView's rows are "photo-entry-<ref>"
  // (photo_picker/1), and LiveView notes each file's ref on the file as
  // `_phxRef`. That is LiveView's own internal name, not a public one:
  // if a LiveView update ever changes it, the waiting ends at once
  // instead (and the previews may come back empty, see whenListed).
  removeHandedOverRows() {
    for (const item of [...this.handedOver]) {
      const ref = item.file._phxRef
      if (ref === undefined || document.getElementById("photo-entry-" + ref)) item.finish()
    }
  },

  // The rows look like the server's rows for picked photos
  // (PhotoUploads.photo_picker/1). Names are set with textContent: a
  // file name must show as plain text, never as markup.
  addPreparingRow(name) {
    const row = document.createElement("div")
    row.className = "flex flex-wrap items-center gap-3 rounded-lg p-2"
    row.setAttribute("data-preparing", "")
    row.dataset.name = name

    const box = document.createElement("div")
    box.className = "w-16 h-16 rounded-lg border border-base-300 flex items-center justify-center"
    box.setAttribute("data-box", "")
    const spinner = document.createElement("span")
    spinner.className = "loading loading-spinner"
    box.appendChild(spinner)

    const text = document.createElement("div")
    text.className = "flex-1 min-w-0"
    const nameLine = document.createElement("p")
    nameLine.className = "text-sm truncate"
    nameLine.textContent = name
    const status = document.createElement("p")
    status.className = "text-sm text-base-content/60"
    status.setAttribute("data-status", "")
    status.textContent = "Preparing photo…"
    text.appendChild(nameLine)
    text.appendChild(status)

    row.appendChild(box)
    row.appendChild(text)
    this.list.appendChild(row)
    return row
  },

  // A photo refused without uploading keeps its row, in red, with the
  // server's message and a ✕ to remove the row. Until it's removed, a
  // save stays on the page and says why (PhotoUploads.start_processing).
  showRefused(row, name) {
    row.removeAttribute("data-preparing")
    row.setAttribute("data-refused", "")
    row.classList.add("border-2", "border-error", "bg-error/10")
    row.querySelector("[data-status]").remove()
    // In the square where a preview would be, as for photos the
    // browser can't show ("no preview").
    const box = row.querySelector("[data-box]")
    box.className += " text-xs text-base-content/60 text-center"
    box.textContent = "too large"

    const button = document.createElement("button")
    button.type = "button"
    button.className = "btn btn-ghost btn-xs text-error"
    button.setAttribute("aria-label", "Remove " + name)
    button.textContent = "✕"
    button.addEventListener("click", () => {
      row.remove()
      this.tellServer()
    })
    row.appendChild(button)

    const message = document.createElement("p")
    message.className = "w-full text-error text-sm font-semibold"
    message.textContent = "Not uploaded: " + this.tooLargeMessage
    row.appendChild(message)
  }
}
