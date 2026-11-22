# Photo speed 3c + 3b: shrinking in the browser, processing on pick

## Context

Part of NOTES "Order of work" step 2, photo speed (item 3). 3a, the
server tuning, is done (`adf0465`): a 12 MP photo now costs ~1.5 s of
CPU on Fly instead of ~3.8 s. Two steps are left, then the security
audit:

- **3c — shrink big photos in the browser before uploading.** Much
  smaller uploads for artists on slow phone connections, and huge
  photos (48–50 MP) reach the server as ordinary ones. That also solves
  most of NOTES #43 (very large photos).
- **3b — process each photo as soon as it's uploaded**, not when the
  artist presses Save. The work happens while the artist types the
  title and description, problems show right away, and Save becomes
  quick.

Order agreed 2026-11-19: 3c, then 3b, then the security audit.

## Already decided (earlier)

- **The browser only shrinks; it never makes the files we serve.** The
  server checks every upload, decodes it and encodes every file it
  serves itself: a crafted image can attack visitors' browsers (e.g.
  the 2023 WebP flaw CVE-2023-4863), and the browser could be bypassed
  anyway. Nothing on the server changes for 3c. (NOTES step 2, item 3.)
- The server keeps `source.webp` ≤4096 px (private) plus the three
  display sizes, and refuses photos over 52 MP or files over 25 MB.

## 3c: shrinking in the browser

### The main rule: a shortcut, never a requirement

If the browser can't shrink a photo for any reason (a format it can't
read, too little memory, an old browser, an error, taking too long),
it **uploads the original file**, and the server handles it as it does
today. So a phone we never tested can't break uploads; at worst it
doesn't get the speed-up. This is also why one trial phone is enough
to start with.

### Proposed design (to confirm)

1. **Which photos get shrunk:** only those **bigger than 4096 px on the
   long side** (the size of the private copy the server keeps). An
   ordinary 12 MP phone photo is 4032 px, so it's uploaded as it is
   (no point compressing it twice). The ones that get shrunk are the
   24, 48 and 50 MP photos and big scans: exactly the slow uploads and
   the costly photos.
2. **Shrunk to 4096 px on the long side**, as a **JPEG at quality
   0.92**. Every browser can write JPEG (Safari can't write WebP from
   a canvas). Quality 0.92 keeps the private copy good; the server
   encodes everything again anyway.
3. **Which formats:** JPEG, WebP, and HEIC where the browser can read
   it (Safari can; Chrome and Firefox, as far as I know, can't, so
   those upload HEIC as it is). **PNG, TIFF and AVIF are left alone**:
   PNG may have transparency, which JPEG would lose; TIFF and AVIF
   are rare. **A WebP is shrunk only if it's an ordinary photo**
   (decided 2026-11-20): WebP can also have see-through parts, or be
   moving (animated), and a JPEG can have neither (see-through parts
   would turn black; only the first frame would be kept). The file's
   first 30 bytes say which it is ("RIFF container": the `VP8 `
   layout is always plain, `VP8L` has an "alpha is used" bit, `VP8X`
   has flags for alpha and animation), so the hook reads them first
   and leaves alone a WebP that has either, or whose header it doesn't
   recognise. The size limits still apply to photos left alone (25 MB
   refused before upload, over 52 MP refused in the browser when it
   can read the size, and NOTES #43 for the big ones in between).
4. **The file keeps its name** with `.jpg` instead of the old ending
   (e.g. `IMG_6457.HEIC` → `IMG_6457.jpg`), so the artist recognises it
   in the list.
5. **What the artist sees:** "Preparing photo…" in the photo's spot
   while it's being shrunk (a second or two), then the usual upload bar.
6. **How it fits LiveView:** the artist picks files with an ordinary
   file input watched by a small JavaScript hook; the hook shrinks
   what it can and hands the files (shrunk or original) to the hidden
   LiveView upload with `this.upload(name, files)`. The server side,
   the 25 MB check and the 5-photo limit stay as they are.
7. **Upright and private:** browsers turn the photo upright using its
   orientation note when drawing it, and the shrunk copy carries no
   metadata at all (no GPS). The server still strips everything.
8. **A time limit:** if shrinking one photo takes over ~15 s (an old
   phone with a 50 MP photo), give up and upload the original.
9. **Photos over the server's 52 MP limit** (the developer's point,
   2026-11-19: don't upload what the server will refuse):
   - if the browser can shrink it, it does, and the photo is accepted
     like any other (e.g. a Samsung 200 MP photo just works: the 52 MP
     limit protects the server's memory, and a shrunk photo doesn't
     threaten it);
   - if it can't (can't read the format, runs out of memory, hits the
     time limit) and the photo is over 52 MP, **the browser refuses it
     without uploading**, with the "too large" message and the guide
     from NOTES #33;
   - the browser only knows the pixel count of formats it can read.
     For the others (mainly HEIC in Chrome/Firefox), the upload goes
     ahead and the server refuses it right after it arrives, as today
     (it reads only the header: milliseconds). Rare: it takes an
     over-52 MP HEIC on a computer.
   So with the "upload the original" rule above, "original" means
   "original, unless it's known to be over 52 MP".
   - **No separate size cap in the browser** (decided 2026-11-19): a
     browser cap can't protect the server (an attacker skips our
     page); the server's own limits do, plus a per-account upload
     rate limit (NOTES step 5). The browser tries any photo it can
     read; the time limit (point 8) and point 9's refusal cover a
     photo too big for the phone.
   - **Refusing is fine for the rare case** (developer, 2026-11-19): a
     phone that takes 200 MP photos can most likely shrink them itself;
     a 200 MP photo uploaded from an older computer that can't may
     simply be refused. Tips on making a photo smaller, maybe with a
     link to a tool, come later (NOTES #33).

### Questions the trial answers

A small private test page that runs entirely in the phone's browser
(nothing is uploaded anywhere): pick photos, see the original's type,
size and dimensions, the shrunk size, how long shrinking took, and the
shrunk copy with a button to switch to the original in the same spot.
The big test photos are made on the Mac (see "The trial page" below):
an iPhone browser can't make a picture that big itself. On the
developer's iPhone (3–4 years old) and on the Mac (Safari, Chrome,
Firefox):

- What does Safari hand the page for an iPhone photo: HEIC, or
  already a JPEG? (Earlier finding: iPhone Safari converts HEIC to
  JPEG only when the form doesn't list HEIC as accepted; ours does.)
- Can it read and shrink a 48 MP photo, and how long does it take?
  Older iPhones limit how big an image the browser handles at once.
  And what happens with a photo over 52 MP (the 60 MP test photo):
  shrunk, or does it fail, and how?
- Do the colours stay right? iPhone photos use the wider "Display P3"
  colour range; drawing them in the browser may shift them slightly.
- Does the photo come out upright?

The results go into this plan before the hook is written.

**The trial page** was `priv/static/trials/photo-shrink.html`, at
`/trials/photo-shrink.html` (behind the site password on the preview;
`trials` was in `ArtsyNeighborWeb.static_paths/0`). Both were
temporary and were removed once 3c was done (2026-11-20; the page is
in git history, commit `806e423`). It can
try two ways of shrinking (picture + canvas, or `createImageBitmap`
with resize) and two canvas colour spaces (sRGB, Display P3), and
keeps a text log of all results to copy. It follows the rules above:
PNG/TIFF/AVIF left alone, a WebP left alone unless its header says
it's an ordinary photo (point 3), and a photo it can't shrink is
reported as "would upload the original", or "would refuse it" if it's
over 52 MP. Both ways first read the photo's size from an `<img>` (the
real version needs it too); a big original is only shown when asked
for. WebP test files of each kind (simple lossy, simple lossless,
lossless see-through, extended still, extended see-through, moving)
and their script are with the other test photos; in Chromium all were
sorted correctly, as were a fake `.webp` and a JPEG named `.webp`
(left alone: header not recognised). Generated test photos (never real
ones: GPS) and the script that made them are outside the repo, in
`~/Code/artsy-neighbor-design/photo-trial/`: 48 MP JPEG, 48 MP HEIC,
60 MP JPEG (over the limit), and a 24 MP JPEG stored sideways with an
orientation note. A first check in Chromium on the Mac (2026-11-19):
both ways work, 48 MP → 4096 × 3072 in 0.3–0.7 s, the sideways photo
comes out upright, HEIC can't be read (as expected).

### Trial results: the developer's iPhone (2026-11-20)

Safari 27.2 on iOS 27 (the browser line says "iPhone OS 18_7": Apple
froze that number), screen 375 × 812 at 3×. Test files picked through
"Choose File" from Downloads (AirDrop refused the mixed batch; saving
to Downloads worked). Times are the total per photo.

| Photo | Picture + canvas | createImageBitmap |
|---|---|---|
| 48 MP JPEG (11.3 MB) | 0.53 s → 3.0 MB | 0.99 s → 4.6 MB |
| 60 MP JPEG (14.0 MB) | 0.55 s → 1.8 MB | 1.4 s → 4.7 MB |
| 48 MP HEIC (16.1 MB) | 0.84 s → 2.8 MB | 1.1 s → 4.5 MB |
| 24 MP sideways JPEG (5.5 MB) | 0.41–0.44 s → 2.5 MB | 0.68 s → 4.0 MB |

What this answers:

- **A 48 or 60 MP photo is no problem for this phone:** shrunk in
  0.5–1.4 s, no crash, far below the 15 s limit, and faster than the
  server (~1.5 s CPU for an ordinary photo on Fly). Uploads become 4–6
  times smaller.
- **Safari reads HEIC** and hands it over as `image/heic` for a file
  picked from Files/Downloads.
- **From Photo Library, the iPhone converts HEIC to JPEG while the
  photo is picked**, even though our form lists `.heic` as accepted
  (this corrects the earlier assumption, "Questions the trial answers"
  above). The developer's four own photos (HEIC on the phone: AirDrop
  to the Mac gave `.heic` files, so the camera saves "High
  Efficiency") reached the page as `image/jpeg`, named `IMG_7821.jpeg`
  etc., 3.1–4.6 MB for 12 MP. Good for us: the server can shrink a
  JPEG while reading it, a HEIC it must decode in full (NOTES #43).
  Left as it is.
- **Colours:** no visible difference between original and re-made
  copy for the developer's own (P3) photos, with an sRGB canvas or a
  Display P3 one, with both ways; file sizes practically the same.
  So the hook uses the default sRGB canvas (the server converts every
  photo to sRGB anyway).
- **Re-making an ordinary 12 MP photo makes it bigger** (e.g. 3.8 →
  4.4 MB at quality 0.92), which confirms the rule: only photos over
  4096 px are shrunk. Times for re-making them: 0.35–0.53 s (picture
  + canvas), 0.54–0.65 s (createImageBitmap); same sizes with both.
- **Upright:** the sideways photo was reported as 4000 × 6000 (stored
  6000 × 4000) and shrunk to 2731 × 4096, with both ways.
- **No visible difference** between original and shrunk copy for any
  test photo (the developer switched between them on each).
- **WebP:** Safari reads it, and the header check sorted all six test
  files as in Chromium (three ordinary ones shrunk; the two
  see-through ones and the moving one left alone). Same result with
  both ways: 0.35–0.50 s with picture + canvas, 0.53–0.68 s with
  createImageBitmap, and the *same* file sizes with both (these test
  pictures are smooth, without grain; the JPEG/HEIC ones have grain,
  and there createImageBitmap's files were bigger, so it keeps more
  grain, and real photos will likely show a smaller size gap). A tiny, smooth WebP (107 KB) became a bigger JPEG
  (653 KB): no rule needed, as the shrunk copy is still cheaper for
  the server and such small uploads are quick anyway.
- **Which way:** "Picture + canvas" is 1.5–2.5 times faster *and*
  gives smaller files, with no visible difference, and works in every
  browser. Chosen for the hook (see below).

- **"Take Photo" in the picker** gives a JPEG (3.9 MB, 12 MP, upright
  3024 × 4032), always named **`image.jpg`**: several photos taken
  this way all have the same name. Harmless for the server (storage
  uses its own names), but the 3b upload box must show each photo's
  preview, not only its name. Times and sizes as for library photos
  (0.42–0.50 s picture + canvas, 0.66–0.67 s createImageBitmap, same
  size, no visible difference, sRGB or Display P3).

**Decided 2026-11-20 (the developer, from the trial): the hook uses
picture + canvas with the default sRGB canvas.** The iPhone part of the trial is
complete; Safari and Firefox on the Mac are optional.

**Firefox 160 on the Mac (2026-11-20, picture + canvas, sRGB), as a
sanity check:** HEIC can't be read ("would upload the original", as
expected: the server handles it); 48 and 60 MP JPEGs shrunk in about
0.3 s; the sideways photo upright (2731 × 4096); all six WebPs sorted
as in Chromium and on the iPhone; no visible difference. So all three
browser engines (WebKit, Chromium, Gecko) agree. Safari on the Mac
was skipped: same engine as the iPhone. With createImageBitmap,
Firefox did the same, a little slower (48 MP: 0.42 s instead of
0.29 s) but with *smaller* files (2.8 MB instead of 3.5 MB), the
opposite of Safari. So file size depends on the browser, not the
way; speed favoured picture + canvas in every browser, which with
its simplicity keeps the decision as it is.

### What was built (2026-11-20)

**The hook:** `assets/js/photo_shrink.js` (`PhotoShrink`, registered
in `assets/js/app.js`), on a wrapper around the file picker in
`ArtsyNeighborWeb.PhotoUploads.photo_picker/1`, so all four photo
forms have it. It catches the artist's pick before LiveView does
(listening in the "capture" phase; LiveView's own later events are
let through, as they come from code, not from the artist), prepares
the photos one after another, and hands each to LiveView with
`this.upload` as soon as it's ready. The shrinking itself is the trial
page's "picture + canvas" way with the default sRGB canvas. The
numbers and the "too large" wording come from the server
(`Images.max_pixels/0`, `source_max_side/0`, `too_large_message/0`,
as `data-*` attributes), so they can't drift apart.

**Added beyond the design above** (some from the code review):

- **Save waits for the browser.** The hook keeps the server informed
  (event `photo_picker_state`: still preparing? which photos were
  refused here?), handled in `PhotoUploads` through `attach_hook/4`,
  so the forms didn't change. A save while a photo is still being
  prepared stays on the page ("Your photos are still being prepared.
  Please wait until they show a bar, then save again."), as it does
  for photos still uploading; a save while a photo refused in the
  browser is still shown stays too ("Your photo … was NOT uploaded:
  This photo is too large. Remove it with ✕ …"), so it can't be
  quietly left out. Either message goes as soon as the browser's state
  changes. The event comes from the browser, so the server takes only
  true/false and a short list of names from it.
- **What gets shrunk is decided by the file's first bytes**, not its
  name or type alone: only JPEG, HEIC and ordinary WebP, and only if
  the name's ending matches. Otherwise a big GIF or BMP (which the
  server refuses) could have come in as a JPEG made here. Everything
  else goes up as it is, and the server decides as before.
- **PNG and WebP sizes are read from those first bytes**, so a big
  PNG is refused (or passed on) without loading the picture.
- **After the 15 s limit,** the abandoned shrinking is told to stop at
  its next step, and the next photo waits for it to finish (at most
  30 s more), so a slow phone never holds two big photos at once.
- **Each photo waits for LiveView before the next one.** Found in the
  browser checks: a photo handed over before LiveView had answered
  for the previous one got an empty preview (in all three engines,
  now and then). The hook now waits until LiveView's row for the
  photo appears (at most 10 s); its "Preparing photo…" row stays
  until then, so the photo never vanishes from the list in between.
  This uses a LiveView-internal name (`_phxRef`, see the comment in
  the hook): if a LiveView update ever changes it, the waiting simply
  ends at once.
- **Side effects:** the 25 MB limit now applies only to photos that
  aren't shrunk (a 30 MB photo shrunk to 3 MB goes through, which is
  fine for the server); a big HEIC shrunk in Safari arrives as a JPEG
  and so gets a preview.

### Tests

The server side has LiveView tests (`vendor_product_form_test.exs`):
the picker carries the hook and the server's numbers; a save waits
while photos are being prepared, and while a photo refused in the
browser is shown; the messages go when the state changes; a malformed
`photo_picker_state` event doesn't crash the page. There is no
JavaScript test setup (NOTES #19 discusses a browser suite), so the
hook was checked by hand (2026-11-20) in all three browser engines,
through Playwright on the dev site: Chromium 158, Firefox 159 and
WebKit 27.2 (Safari's engine). In each: 48 and 60 MP JPEGs shrunk
(0.2–0.3 s), a 12 MP JPEG uploaded as it is, a 63 MP PNG refused
without uploading, a broken file and a big GIF (also renamed `.jpg`)
passed on for LiveView or the server to refuse, ordinary WebPs shrunk,
see-through and moving WebPs left alone, the sideways photo upright,
every preview shown, and a full save storing the shrunk photos
(`source.webp` 4096 × 3072, and 2731 × 4096 for the sideways one).
WebKit on the Mac reads HEIC, so there a big HEIC is shrunk too;
Chromium and Firefox pass it on unread. Generated test files only
(`~/Code/artsy-neighbor-design/photo-trial/` plus a few made the same
way); the test drafts were deleted afterwards.

Not tried in a browser (checked by reading): the 15 s limit, and the
profile form's Previous button pressed while a photo is still being
prepared.

**On the developer's iPhone, on the preview site (2026-11-20, after
deploying `0c4dcc9`)**, read from the server's "Photo stored" log
lines:

| Photo | On the phone | What the server received |
|---|---|---|
| 2 × Take Photo (`image.jpg`) | 12 MP | 4032 × 3024, 4.6 MB: as it is |
| Photo Library (`IMG_7820.jpeg`) | 12 MP | 4032 × 3024, 4.3 MB: as it is |
| `test-48mp.jpg` (Downloads) | 8064 × 6048, 11.3 MB | 4096 × 3072, 2.7 MB: shrunk |
| `test-60mp.jpg` (Downloads) | 60 MP, 14.0 MB | 4096 × 3049, 1.8 MB: shrunk |
| `test-sideways.jpg` (Downloads) | 24 MP, stored sideways, 5.5 MB | 2731 × 4096, 2.4 MB: shrunk, upright |

- The phone's own photos are just under 4096 px, so they go up as
  they are, as designed: everyday photos are not touched.
- The big ones were shrunk on the phone; uploads 2–8 times smaller,
  and the 60 MP photo, which the server refuses unshrunk, went
  through. The developer checked the stored photos: they look right,
  the sideways one upright. No errors in the log.
- **The developer didn't notice "Preparing photo…"**, not even for
  the big photos. Expected: on this phone shrinking takes about half
  a second, and the rows appear under the photos already in the list,
  possibly just out of view. A slower phone or a bigger photo keeps
  it up longer. Left as it is.
- **Not explained:** the server took 3.5–4 s to process each shrunk
  test photo, against ~2 s for the developer's own 12 MP photos of
  about the same size. Likely the picture content (the generated test
  photos are fine stripes and grain, harder for the WebP encoder) or
  the preview's shared CPU slowing down after several photos in a
  row; not the hook, which works before the server sees the file. To
  look at in the measuring step (order of work, step 6).

3c is done. The trial page (`priv/static/trials/photo-shrink.html`)
and its `trials` entry in `static_paths/0` were removed afterwards;
the page is still in git history (commit `806e423`), should it be
wanted again.

## 3b: processing on pick

### Today

Photos upload as soon as they're picked (`auto_upload`), but nothing
is processed until Save: then each photo is checked, resized and
stored in a background task, one after another, while the page shows
"Saving your photos…" (`ArtsyNeighborWeb.PhotoUploads`).

### Design (agreed 2026-11-20)

1. **As soon as a photo has finished uploading, the server processes
   it** (checks, makes `source.webp` and the three sizes) **into a
   temporary folder on the server, not into storage.** Each photo shows
   its own status: "Checking the photo…" (spinner), then "Ready ✓", or
   the problem in plain words ("This photo is too small…") in red with
   its ✕ to remove it. ("Preparing photo…" is already the browser's
   shrinking step, so the server's step has a different name.)
2. **Save only stores and records:** it copies the ready files to
   storage and makes the database rows, still in the background task
   with "Saving your photos…", but quick (storing took 0.1–0.24 s per
   photo on Fly). It also works for a new product, which has no id
   (and so no storage folder) until it's saved: the folder is chosen
   only at Save. In `Images`: `prepare_upload` (checks + the four
   files) and `store_prepared` (copy to storage); `process_upload/3`
   stays as the two together, for the sample data and the timing tool.
3. **If Save is pressed while photos are still being checked, Save
   waits by itself** (developer's choice, 2026-11-20): the text is
   saved, "Saving your photos…" shows, and as soon as the photos are
   ready they're stored and the form carries on as usual. The artist
   presses once. (Photos still uploading, or still being shrunk in the
   browser, keep today's message and "save again": those usually
   finish while the artist is still on the photo section.)
4. **A photo the server refused** (not a photo, too small, too large)
   **blocks Save** until it's removed with ✕, as photos refused in the
   browser already do: trying again can't help when the photo itself
   is the problem. The text is still saved, as today.
5. **"The site is busy" or "Something went wrong"** (problems on our
   side): the photo waits longer for its turn than a button press
   could (no browser time-out here); if it still fails, its row says
   so and gets a **Try again** button. Save also tries such photos
   once more.
6. **Nothing is left behind:** removing a photo with ✕ deletes its
   files; if it's still being worked on, it's let finish and the result
   thrown away (stopping it halfway could leave a file being written).
   A small watcher process deletes a page's temporary folder when the
   page's process ends, and at start-up and once an hour the server
   deletes leftover folders older than a day (e.g. after a crash).
7. **The limiter stays:** one page's photos are processed one after
   another, holding one slot at a time, as today. Storing at Save
   doesn't take a slot (it's copying files, not image work).
8. **The upload box stays LiveView's own list** (changed from the
   first draft, which planned our own list): LiveView can keep a
   finished photo in its list and just tell us where the file is
   (`{:postpone, ...}`), so previews, ✕, the 5-photo limit and the 3c
   hook (which waits for LiveView's row of each photo) keep working;
   `PhotoUploads` adds one status line per photo, and handles the
   "upload finished" and "photo ready" signals itself (`progress:`
   callback, `attach_hook` on `:handle_async`), so the forms barely
   change.

### What was built (2026-11-20)

- **`Images`:** `prepare_upload/4` (checks + the four files into a
  work folder, holding a Limiter slot; errors come back as
  `{:refused, message}` or `{:failed, message}`, so the page knows
  whether trying again can help), `store_prepared/2` (copy to storage
  and the timing log line; no Limiter slot) and `discard_prepared/1`.
  `process_upload/3` is now the two together, so the sample data and
  the timing tool work as before.
- **`Limiter.run/2`** takes `wait_ms:` (and `server:`, for its tests).
  A photo checked on pick may wait **3 minutes** for a slot instead of
  30 s (`prepare_wait_ms` in `PhotoUploads`, can be set in config).
- **`ArtsyNeighbor.Images.PreparedFolders`** (new, started with the
  app): one temporary folder per page under
  `<tmp>/artsy_neighbor_prepared/`, deleted when the page's process
  ends; at start-up and hourly, folders older than a day that no open
  page uses are deleted.
- **`PhotoUploads`:** a `progress:` callback starts checking each photo
  when its upload is done (one at a time per page, in the order
  listed); an `attach_hook` on `:handle_async` takes the result; a
  `"retry_photo"` event (the Try again button) is handled next to the
  browser's `"photo_picker_state"`. Status per photo in the new
  `:photo_prep` assign. `start_processing/5` and `finish_processing/3`
  keep their shape, so the four forms only pass `photo_prep` to the
  picker.
- **Save with a photo that can't be used** stores the good ones and
  stays on the page, asking to remove it ("Remove it with ✕ and pick
  another photo, then save again."); with only problems on our side it
  says "Press Try again next to it, or save again."

**After the code review (2026-11-20), all 10 findings fixed:**

- Each step in `Images` says itself whether its error is the photo's
  or ours (no more telling them apart by the message text). A file
  that can't be written after the photo was decoded (e.g. a full disk)
  is now "failed" (Try again), not "couldn't read this file as a
  photo".
- ✕ on a photo being checked stops its task at once (it may only be
  waiting for its turn), and its files are deleted once the task has
  really ended. The Limiter drops a waiter that dies from its line.
- When a photo fails on our side, the photos queued after it on the
  same page get the same message instead of each waiting 3 minutes in
  turn; one Try again retries them all. So a waiting Save ends within
  about 3 minutes, not up to 15.
- Storing protects each photo on its own (a crash fails only that
  photo), and the page is told after each photo stored, so even if the
  storing task died, no photo is stored twice.
- While a save waits, only its own photos are checked; one picked
  later is checked after the save.
- `PreparedFolders` deletes a closed page's folder a minute later, in
  the background (a photo step still finishing can't recreate it, and
  other pages aren't held up), and keeps a `.owner` file in each folder
  (the page's process and the server's operating-system process id),
  so after a restart of `PreparedFolders` it watches the open pages'
  folders again. Tests use their own folder (`config/test.exs`).
- Smaller: the test helper's wait says clearly when it times out;
  CLAUDE.md's photo rule names the two halves; the folder is
  validated once.

### Very large photos (NOTES #43) fit in here

With processing on pick, the server knows a photo's pixel count right
after it arrives (reading the header takes milliseconds), before doing
any work. So, for a photo the browser couldn't shrink:

- above a limit decided from a measurement (#43 step 1): ask "This
  photo is very large and will take a while to prepare. Choose a
  smaller photo, or continue?", with the guide from #33;
- if the artist continues: a separate limiter lane with one slot for
  big photos, so ordinary photos never wait behind one, and a longer
  wait allowed there.

**Which photos get the warning** (decided 2026-11-20): every photo
over the limit that reaches the server unshrunk, whatever the reason:
a see-through or moving WebP, any PNG/TIFF/AVIF, HEIC the browser
can't read, or a photo whose shrinking failed. The message names the
reason in plain words when it's known (draft in NOTES #43, with two
buttons: [Use this photo] / [Choose a different photo]), and the
browser asks **before uploading** whenever it knows both the size and
the reason; the server asks after the upload only for files the
browser can't read. Related: a moving image becomes a still one on
the site (the server keeps the first frame) — the artist should be
told, at any size (NOTES #44).

**Decided 2026-11-19: right after 3b**, as its own step and commit, once
3c shows how many big photos still reach the server (3b touches the
same code, but is already big).

#### Measured 2026-11-21 (#43 step 1)

Test photos generated on the Mac (never the developer's own photos),
kept in `~/Code/artsy-neighbor-design/photo-trial/`.

On the Mac, `Images.prepare_upload/4` only (checking and making the
files, nothing stored), CPU time and the memory added on top of the
idle app (~120 MB):

| Photo | CPU | Memory added |
|---|---|---|
| 12 MP JPEG (a typical phone photo) | 0.55 s | +240 MB |
| 12 MP HEIC | 0.95 s | +325 MB |
| 48 MP JPEG | 0.74 s | +275 MB |
| 19 MP PNG (the largest that fits in 25 MB) | 0.7 s | – |
| 48 MP AVIF | 1.7 s | +490 MB |
| 48 MP HEIC | 2.9 s | +615 MB |

A JPEG is shrunk while it's read, so its size hardly matters; HEIC
and AVIF are decoded in full. PNG and TIFF photos can't be big: the
25 MB upload limit stops them first (a 48 MP PNG is 69 MB, a 48 MP
TIFF 76 MB). The Mac's memory numbers are high because libvips runs
a thread per core, and the Mac has many.

On the Fly preview (1 shared CPU, 1 GB), through the real product
form in Chrome (which can't read HEIC and leaves AVIF alone, so both
reach the server at full size); "peak" is the whole server's:

| Photo | Preparing | Peak |
|---|---|---|
| 48 MP HEIC | 7.8–8.7 s | ~570 MB |
| 48 MP AVIF | 6.5 s | (≤ 571 MB) |
| *ordinary phone photos, for comparison* | *~2 s* | *~470 MB* |

Uploading through the form, two photos never overlapped: each 15 MB
upload took longer than preparing the one before. So the two-at-once
case was forced on the server (the HEIC copied over with
`fly ssh sftp put`, two `prepare_upload` calls started together via
`rpc`, nothing stored, files deleted afterwards): **17 s each, peak
757 MB**.

What this shows:

- Memory is safe: the limiter allows two photos at once, and two big
  ones together leave ~250 MB spare on the 1 GB server.
- The cost is time, and it's shared: the server has one CPU, so two
  photos prepared side by side each take twice as long. Running two
  big photos at once makes nothing faster; it only makes everyone
  else wait (an ordinary photo arriving then would wait up to ~17 s).

#### Decided 2026-11-21

This replaces the question with two buttons and the separate lane
above.

1. **A big photo may use only one of the two limiter slots.** "Big"
   means HEIC or AVIF (libvips' `heifload`) over about 20 MP; the
   server knows both from the header, in milliseconds, before any
   work. Other big photos wait their turn for that one slot, with a
   longer wait allowed than the usual 30 s (e.g. the 3 minutes Try
   again already uses). Ordinary photos always find a slot; at worst
   they share the CPU with one big photo (~4 s instead of ~2). With
   one CPU, this costs the big photos nothing overall.
2. **No question.** The worst case is 8–17 s, not minutes, and a
   question would give older artists a decision they don't need.
   Instead the photo's row says e.g. "Large photo — this one takes a
   little longer…" while it waits and is prepared; ✕ still removes
   it.
3. NOTES #44 (telling the artist that a moving image becomes a still
   one) is built in the same step, since it changes the same row
   messages.

#### Built 2026-11-21

- `Limiter.run/2` takes `big: true`. Big photos may hold at most
  `max_big` slots (config, 1). When a slot frees up, it goes to the
  first one in line *that may start*: a big photo waiting for the big
  photos' slot keeps its place, and ordinary photos behind it go
  ahead.
- `Images.prepare_upload/4` now checks the header (format, size)
  **before** waiting for a slot, so a photo that can't be used is
  refused at once, and the server knows whether a photo is big before
  it waits. `Images.big_photo?/3`: `heifload` over `big_photo_pixels`
  (config, default 20 MP; a test lowers it). The new `:on_header`
  option reports `%{big: ..., moving: ...}` (moving: the file's
  `n-pages` header is over 1). *Changed after the review, see below:
  PNG/TIFF count too, and `moving` became `pictures`.*
- `PhotoUploads`: the background task sends the page
  `{:photo_header, ref, info}`; the photo's row then says "Large photo
  — this one takes a little longer…" instead of "Checking the
  photo…", and a moving image gets "This is a moving image, or a file
  with several pictures. Only the first picture will be shown on the
  site." (wider than the draft: a TIFF with several pages ends up the
  same way). Both "checking" lines carry `data-photo-checking`, which
  the tests' `wait_for_photo_work/2` looks for.
- The "longer wait" for big photos needed nothing new: photos checked
  on pick already wait up to 3 minutes for a slot (`prepare_wait_ms`).
- Tests: `limiter_test.exs` (4: at most `max_big`, a waiting big photo
  doesn't hold up ordinary ones, the config value, `:busy`),
  `images_test.exs` (`:on_header` for a JPEG, a refused photo and a
  moving WebP, which keeps one 1487 × 998 picture; `big_photo?/3`),
  a new `ImagesBigPhotoTest` module (an AVIF with the limit lowered:
  big; waits while another big photo is prepared), and
  `photo_checking_test.exs` (4: "Large photo", the moving-image note,
  and neither for an ordinary photo). The test photos (a small AVIF,
  a two-picture WebP) are made from the cat-sculpture site image in
  `test/support/photo_upload_helpers.ex`.
- Checked in Chromium on the dev site with `test-48mp.heic` (Chromium
  can't read HEIC, so it arrives unshrunk) and the moving WebP from
  the photo trial: both messages appear as intended.
- After the code review (2026-11-21):
  - **PNG and TIFF over 20 MP count as big too.** libvips decodes
    them in full as well; they're rare at that size (the 25 MB limit
    stops most), but a compressed scan could get through.
  - **The header is read without keeping the photo open.** Only plain
    values (format, width, height, pictures) are kept while a photo
    waits for its slot, and the opened file is let go at once: for
    HEIC, libheif may hold the whole file in memory while it's open,
    and a photo can wait minutes.
  - **The note is given only where it's true:** "This is a moving
    image. Only its first picture will be shown on the site." for a
    moving WebP, "This file has several pages. Only the first page
    will be shown on the site." for a TIFF with several pages, and
    nothing for HEIC/AVIF. There `n-pages` counts the top-level
    pictures, e.g. the two of an iPhone spatial (3D) photo, and libvips
    shows the main one, the photo the artist sees.
  - The tests that make an AVIF are tagged `:heic` (they need libheif,
    like the existing AVIF test); "an ordinary photo just says Checking
    the photo" now waits until the page knows the header (checked: it
    fails if `big_photo?/3` always says yes); a test for a TIFF with
    two pages.

### Tests

LiveView tests (the existing upload helpers): a picked photo becomes
"Ready" before Save; a refused one shows its message before Save; Save
stores ready photos and makes their rows; Save with a photo still
being prepared waits; removing a photo and closing the page delete its
temporary files; the start-up clean-up removes only old folders; the
new-product form works without a product id.

*Written 2026-11-20:* `test/artsy_neighbor_web/live/photo_checking_test.exs`
(11 tests on the vendor product form: all of the above, plus "site
busy" → Try again, Save retrying a failed photo, ✕ while a photo is
being checked or waiting for its turn, and the photos after a busy
one not being left waiting; to make a photo wait, the tests hold all
the app's Limiter slots, safe because the module isn't async),
`test/artsy_neighbor/images/prepared_folders_test.exs` (7, incl. the
restart cases), four tests for `prepare_upload`/`store_prepared` in
`images_test.exs` (incl. a folder that can't be written to counting as
"failed"), two in `limiter_test.exs` (`wait_ms:`, a waiter that dies). The existing upload tests of all four
forms pass unchanged apart from the wording of the row message; the
profile form tests now wait with `wait_for_photo_work/2`
(`test/support/photo_upload_helpers.ex`), since checking one photo
starts the next background step.

## Order of work

1. This plan agreed (the "to confirm" and "to decide" points).
2. The trial page; results added here.
3. 3c: the hook, the fallbacks, the "Preparing photo…" state. Checked
   in three browsers and on the developer's phone. One commit.
   *DONE 2026-11-20: built and checked in three browsers (`0c4dcc9`),
   then on the developer's iPhone; trial page removed (see "Tests").*
4. 3b: processing on pick, the new upload box, the clean-up. One or two
   commits, with a code review before committing.
5. #43: the warning and the big-photo lane. *Measured and decided
   2026-11-21 (see "Very large photos"): one slot for big photos, a
   row message instead of a question. Built the same day, with #44.*
6. Measure on Fly: a series of photos, and the time from pick to
   "Ready" and from Save to done.
