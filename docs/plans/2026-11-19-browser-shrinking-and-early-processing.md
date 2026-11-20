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

### Tests

The server side doesn't change, and its tests stay. There is no
JavaScript test setup (NOTES #19 discusses a browser suite), so the
hook is kept small and checked by hand: in Chromium, WebKit and
Firefox through the Playwright tool (big JPEG gets shrunk, 12 MP JPEG
and PNG don't, an ordinary big WebP gets shrunk while a see-through
or moving one doesn't, a broken file falls back to the original, an over-52 MP
photo the browser can't shrink is refused without uploading), and on the
developer's phone on the preview site.

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
4. 3b: processing on pick, the new upload box, the clean-up. One or two
   commits, with a code review before committing.
5. #43: the warning and the big-photo lane.
6. Measure on Fly: a series of photos, and the time from pick to
   "Ready" and from Save to done.
