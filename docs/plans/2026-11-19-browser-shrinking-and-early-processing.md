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

**The trial page** is `priv/static/trials/photo-shrink.html`, at
`/trials/photo-shrink.html` (behind the site password on the preview;
`trials` is in `ArtsyNeighborWeb.static_paths/0`). Both the page and
that entry are temporary: remove them once 3c is done
(`Release.check_before_launch/0` refuses while they're there). It can
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
prepared. Still to do: the developer's iPhone on the preview site
(real Photo Library photos, a real phone connection); then remove the
trial page and its `trials` entry.

## 3b: processing on pick

### Today

Photos upload as soon as they're picked (`auto_upload`), but nothing
is processed until Save: then each photo is checked, resized and
stored in a background task, one after another, while the page shows
"Saving your photos…" (`ArtsyNeighborWeb.PhotoUploads`).

### Proposed design (to confirm)

1. **As soon as a photo has finished uploading, the server processes
   it** (checks, makes `source.webp` and the three sizes) **into a
   temporary folder on the server, not into storage.** Each photo shows
   its own status: "Preparing…", then "Ready", or the problem in plain
   words ("This photo is too small…") with its ✕ to remove it.
2. **Save only stores and records:** it copies the ready files to
   storage and makes the database rows. That's quick (storing took
   0.1–0.24 s per photo on Fly). It also works for a new product,
   which has no id (and so no storage folder) until it's saved.
3. **If Save is pressed while photos are still being prepared**, the
   form waits for them, as it now waits for uploads ("Your photos are
   still being prepared…").
4. **Nothing is left behind:** if the artist removes a photo, leaves
   the page or closes the browser, its temporary files are deleted. A
   small watcher process deletes a page's temporary folder when the
   page's process ends, and at start-up the server deletes leftover
   folders older than a day (e.g. after a crash).
5. **The limiter stays:** one artist's photos are processed one after
   another, holding one slot at a time, as today.
6. **The upload box changes:** today it lists LiveView's own upload
   entries. Processing on pick takes the file over from LiveView once
   it has arrived, so the box becomes our own list of "photos being
   added" (preview, name, status, ✕). This is the biggest part of 3b,
   in all four forms that take photos (through `PhotoUploads`).

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

### Tests

LiveView tests (the existing upload helpers): a picked photo becomes
"Ready" before Save; a refused one shows its message before Save; Save
stores ready photos and makes their rows; Save with a photo still
being prepared waits; removing a photo and closing the page delete its
temporary files; the start-up clean-up removes only old folders; the
new-product form works without a product id.

## Order of work

1. This plan agreed (the "to confirm" and "to decide" points).
2. The trial page; results added here.
3. 3c: the hook, the fallbacks, the "Preparing photo…" state. Checked
   in three browsers and on the developer's phone. One commit.
   *Built and checked in three browsers 2026-11-20 (see "What was
   built"); the phone check and the trial page's removal follow in a
   small second commit.*
4. 3b: processing on pick, the new upload box, the clean-up. One or two
   commits, with a code review before committing.
5. #43: the warning and the big-photo lane.
6. Measure on Fly: a series of photos, and the time from pick to
   "Ready" and from Save to done.
