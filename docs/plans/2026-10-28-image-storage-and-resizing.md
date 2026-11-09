# Step b: image Storage module + automatic resizing (with iPhone HEIC support)

## Context

Part of NOTES "Order of work" step 2 (b of a–c; a = cleanup, done in `705b072`).
Today every upload form copies the raw file into `priv/static/uploads/...`
and stores a `/uploads/...` path. That won't survive a Fly deploy, nothing
checks or resizes the photos, and iPhone photos (HEIC) are refused. Goal:
one place that checks, resizes and stores images, so step c (Tigris) only
has to swap where files go. The developer wants HEIC accepted: many
artists will upload straight from iPhones.

## HEIC: how we'd support it

What I found:
- iPhone Safari already converts HEIC to JPEG on upload when the form
  doesn't list HEIC as accepted. But a HEIC file copied to a Mac or PC
  and uploaded from there arrives as HEIC.
- The ready-made ("precompiled") libvips that the Elixir `image` library
  installs by default can't read HEIC (patent-encumbered codec). A libvips
  installed on the system with libheif + libde265 can.

So, **decided 2026-10-28 (option B)**:
- **Server (Fly, step c): system libvips with HEIC.** The Dockerfile
  installs libvips + the libheif HEVC decoder via `apt` (ready-made Linux
  packages) and builds with
  `VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS`. Recorded in the
  deploy runbook.
- **Mac (dev): also system libvips with HEIC** (changed 2026-11-06).
  The original choice (2026-10-28) was the `image` library's ready-made
  libvips without HEIC, because on macOS 14 `brew install vips` had to
  compile ~110 packages from source and failed. After the upgrade to
  macOS 27, Homebrew has ready-made packages again: `brew install vips`
  (8.18.7, libheif 1.23.7 + libde265) took minutes and reads HEIC. So
  dev and server now work the same way. Setup on the Mac:
  `brew install vips`, and `export
  VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS` in `~/.zshrc` (vix
  reads it when it compiles; after changing it,
  `mix deps.clean vix && mix deps.compile vix`).
- Where libvips can't read HEIC (e.g. a future CI machine using the
  ready-made libvips), a HEIC upload gets a plain message instead of
  being processed; everything else works.
- Forms accept `.jpg .jpeg .png .webp .heic .heif .tif .tiff .avif`
  (TIFF for scans and photographers' exports; AVIF from some newer Android
  phones and editors, read by the same libheif). Everything is converted to
  WebP on our side, so the format the artist uploads never matters after
  that.
- Deliberately not accepted: GIF (256 colours, not for artwork photos),
  camera RAW (huge, brand-specific), SVG and PDF (can carry hidden code —
  an upload security risk), BMP (rare, may not be readable).
- The upload area says in plain words what's accepted (e.g. "Photos from
  your phone or camera: JPEG, PNG, HEIC, …"), since computer file
  choosers grey out other formats without explaining why.

## Design

**Keep the `path` column** on `product_images` / `artist_images` (no
migration). It holds either:
- an old-style web path starting with `/` (seed images, today's dev
  uploads, site images) — shown as-is, so **no data conversion needed**;
- or a new storage key like `products/<product_id>/<uuid>` — a folder
  holding `source.webp` (the kept copy, ≤4096px, see below),
  `large.webp` (≤2500px long side), `medium.webp` (≤1600px), `thumb.webp`
  (≤600px).

**No raw uploads are kept** (decided 2026-11-06). Phone photos carry GPS
location (the spike's iPhone photo had 15 GPS fields), and stored files
are reachable by URL (`priv/static/uploads/` in dev, possibly a public
bucket in step c), so a raw original could publish an artist's home
location. Instead of `original.<ext>`, we keep `source.webp`: the upload
upright, WebP quality 95, with all metadata removed, and at most 4096px
on the long side (see "Memory" below; first planned as a full-resolution
`full.webp`, changed 2026-11-09). It serves the same purposes
(regenerating sizes up to 2500px, image embeddings later) at the cost
of one invisible re-encode.

**Public vs private storage** (decided 2026-11-06). In a *public* bucket
anyone can read a file at its plain address (writing and deleting always
need our secret keys); in a *private* bucket every read must be signed
with the keys, so browsers can only fetch files through expiring signed
links that our server generates. Signed links for every image on every
page would mean broken images on stale pages, poor caching, and no
stable images for link previews when artist pages are shared. But
`source.webp` is a high-quality copy of an artist's work and never needs
to be shown. So the split is by purpose:
- **public:** `large.webp`, `medium.webp`, `thumb.webp` (stripped,
  meant to be seen; keys contain a random part, so nothing can be
  guessed);
- **private:** `source.webp`, read only by our server (regenerating
  sizes, embeddings later). Never served, so no signed links needed.

`Storage` therefore takes a visibility (`:public` / `:private`) on
`put/3`. In dev, `Storage.Local` writes public files under
`priv/static/uploads/<key>` (served) and private ones under
`priv/private_uploads/<key>` (not served; gitignored). In step c these
become two Tigris buckets. Left for later: whether 2500px is too
generous for the public `large` size, and removing public sizes when a
product is hard-deleted.

**New modules** (`lib/artsy_neighbor/`):
- `Images` — the one public entry point.
  - `Images.process_upload(tmp_path, client_name, folder)` → checks it's a
    real image (opens it with libvips; extension alone isn't trusted),
    refuses if the long side < 800px with the plain-words message from
    NOTES #24, auto-rotates using the photo's orientation tag, strips
    all metadata (GPS location from phones) *before* writing anything,
    writes `source.webp` + 3 sizes, returns `{:ok, key}` or
    `{:error, message}`. The temporary upload file is never copied into
    storage.
  - `Images.url(path_or_key, size)` → old `/...` path unchanged; a key →
    `Storage.url("<key>/<size>.webp")`.
- `Storage` — behaviour with `put(local_file, key, visibility)`,
  `url(key)` (public files only), `read(key, visibility)` (for the
  server's own use of `source.webp`), `delete_prefix(key)` (deletes
  everything *inside the folder* `key`, i.e. keys starting with
  `key <> "/"`, and only one image's folder, ending in a UUID); backend
  chosen in config. See "Public vs private storage" above.
  - `Storage.Local` — public files under `priv/static/uploads/<key>`,
    URL `/uploads/<key>`; private files under
    `priv/private_uploads/<key>`, never served (dev). Test env points
    both at a tmp folder.
  - (`Storage.S3` comes in step c.)

**Memory** (measured 2026-11-06, decided 2026-11-09). Processing a
photo needs much more memory than its file size; the Fly machine has
512 MB. Peak memory of a fresh process on the Mac (about 110 MB of it
is the process itself; Linux and a release will differ, so these are
relative sizes):

| Upload | First version (full-res `full.webp`, ≤100 MP) | Now (`source.webp` ≤4096px, ≤52 MP) |
|---|---|---|
| 12 MP JPEG | ~375 MB, 1 s | ~370 MB, 1 s |
| 48 MP JPEG | ~790 MB, 2.7 s | ~420–460 MB, 1.2 s |
| 52 MP 16-bit TIFF (worst case allowed) | — | ~520 MB, 2 s |
| 100 MP JPEG | ~1.4 GB, 13 s | refused in 70 ms |

Encoding the full-resolution WebP was the main cost; libvips' thread
count and cache made no difference. Decided: keep `source.webp` at
≤4096px, refuse uploads over 52 MP (phones: 12–24 MP by default, 48–50
MP in optional modes; a Pixel's 50 MP is 50.1 MP), and in step 2 limit
how many photos one machine processes at a time (N, in config,
starting at 2 — not 1, which would become a hidden queue). The
machine's memory and N get decided on the real server before testers
(NOTES, step 2c). Helping artists with too-large photos: NOTES #33.

**Forms** (vendor product, vendor profile, admin product, admin artist):
replace the copy-a-file blocks (`File.cp!` sites, e.g.
`vendor_live/product_form.ex:207-225`, `:259-273`) with
`Images.process_upload/3`; show its error messages next to the upload.
Raise `max_file_size` from 5 MB to 25 MB (phone photos are big; we shrink
them anyway) and fix the mismatched "max 3 MB" message. Product images
stored under `products/<product_id>/`, artist images under
`artists/<artist_id>/`.

**Saving with photos that fail** (decided 2026-11-09). A photo can now
be refused (too small, too large, wrong format, site busy). Retyping a
whole form because of one photo is annoying, and an artist should be
able to save a half-finished product and finish it later, e.g. fix the
problem photo on another computer. So:
- Saving always keeps the text fields (if they're valid). Then each
  photo is processed: photos that pass are stored and get a row;
  a photo that fails is **never stored** — it stays only in the upload
  box on the screen where it was tried, with its plain-words message.
  (LiveView's temporary copy is deleted when the page closes.) The
  Edit form, on any computer, lists only the stored photos.
- Because the product/artist is saved before its photos, it always has
  an id, so the folder layout above (`products/<product_id>/<uuid>`,
  `artists/<artist_id>/<uuid>`) stays.
- After the first save of a new product, the page becomes that
  product's edit page, so saving again doesn't create a duplicate.

**Product `:draft` status** (decided 2026-11-09, temporary until the
dashboard revamp lets artists change product status themselves —
NOTES). Products get a fourth status, `:draft` (the column is a plain
string: no migration). Rules, enforced in `Products` (not only in the
forms, so the admin form and future code follow them too):
- a product with no photos can't be `:available`; it stays `:draft`;
- removing the last photo of an `:available` product moves it back to
  `:draft`, with a message saying so;
- drafts are hidden from the public automatically (`only_available/1`
  requires `:available`); the artist-deactivation cascade only touches
  `:available` products, so it leaves drafts alone.

Vendor product form, for a new or draft product, has three buttons
(an `:available` product keeps its single Save button):
- **Save draft** — saves text and the photos that pass; stays hidden;
- **Preview** — saves the same way, then opens the owner's preview of
  the product page, `/products/:id?preview=1`, following the artist
  page's existing `?preview=1` (works only for the logged-in artist who
  owns the product; anyone else gets the normal public behaviour): the
  page as a buyer would see it, with a "Preview — buyers can't see this
  yet" banner, a "Back to editing" link and the Buy button turned off.
  This also covers NOTES #16's 2026-10-23 item (an artist can't see
  their own unavailable work's page);
- **Publish** — saves and makes the product `:available` if it has at
  least one photo; otherwise it stays a draft with "Add at least one
  photo to publish this product."
Under them, a small clickable "What do these buttons do?" box explains
the difference (not hover tooltips: they don't work on phones and
tablets).

**Artist profile without a photo** (decided 2026-11-09). Onboarding
step 2 no longer blocks on a missing photo; it saves and moves on.
Instead, activation is checked in `Artists`: the dashboard's "Activate
profile" and the admin form refuse to make an artist `:active` without
a profile photo, and say why. Removing the last photo of an `:active`
profile is refused (`Artists.delete_artist_image/1`), with a message
to upload another photo first or, to hide the profile, to use the
dashboard's "De-activate profile" button. Not hidden automatically, on
purpose: deactivating also makes all the artist's products unavailable,
and they don't come back on their own.

**Display** (~30 `src={img.path}`-style sites, e.g.
`components/custom_components.ex`, `product_live/show.ex`,
`artist_live/show.ex`, `order_formatters.ex`): go through
`Images.url(path, size)` — `:thumb` for tiles/cards/order rows,
`:medium` for the product page, `:large` for the large view.

**Out of scope here:** category pictures (admin types a path by hand;
leave as is), deleting files when an image row is deleted (soft-delete
world; note in NOTES), the dead `first.html.heex` template, `wall_art.jpg`
(fix by hand in dev data).

## Order of work (one commit, or two if it grows)

0. Spike: add `{:image, ...}` built against the system libvips, confirm
   it opens JPEG, PNG, WebP, `~/Code/artsy-neighbor-design/IMG_6457.HEIC`
   itself, and a TIFF and an AVIF made from it (with `sips`); that the
   iPhone photo comes out upright and without GPS metadata; and what
   error a HEIC gives with the ready-made libvips (to turn into a plain
   message). If TIFF or AVIF fails, report and drop that one. HEIC on
   the server is confirmed in step c.
   **Spike results (2026-11-06)**, `image` 0.73.0 / `vix` 0.42.0 linked
   to Homebrew libvips 8.18.7:
   - JPEG, PNG, WebP, TIFF, AVIF and the iPhone HEIC all open and
     convert. All formats stay accepted.
   - Rotation: HEIC and AVIF come out upright already (libheif applies
     the rotation). JPEG/PNG/TIFF made by `sips` keep sideways pixels
     plus an orientation tag (6), so `Image.autorotate/1` is needed —
     it works.
   - GPS: the iPhone photo has 15 GPS fields (location in Victoria).
     Written to WebP without stripping, they all survive;
     `Image.remove_metadata/1` removes them. So stripping is essential.
   - Sizes from the 3024×4032 iPhone photo: large (2500) 1.1 MB,
     medium (1600) 436 KB, thumb (600) 25 KB, WebP quality 82.
   - A non-image renamed to `.jpg`: `{:error, ...}` "Failed to find
     load" on open — easy to turn into a plain message.
   - **Gotcha: libvips is lazy.** With the bundled libvips, a HEIC
     *opens* fine (header only) and fails only when the pixels are
     decoded ("Support for this compression format has not been built
     in: HEVC"). So `process_upload` must force a decode early (e.g. the
     first resize) and map that error to the plain message.
   - Guard test added: `test/artsy_neighbor/image_setup_test.exs`
     decodes a small HEVC HEIC (`test/support/images/cat-sculpture.heic`,
     made with `sips` from a site image, no GPS) and fails with fix
     instructions if vix was built against the bundled libvips. Checked
     both ways. (A future CI machine without HEIC would need it tagged
     or libvips installed.) Test images are never made from the
     developer's own photos: they carry GPS.
1. `Storage` + `Storage.Local` + `Images` with tests.
2. Split into two commits (decided 2026-11-09):
   - **2a.** Product `:draft` status and the "needs a photo" rules for
     products and artists (see "Product `:draft` status" and "Artist
     profile without a photo" above), with tests. The vendor product
     form's Save draft / Preview / Publish buttons, the info box and
     the preview page.
   - **2b.** Switch the four upload forms to `Images.process_upload/3`
     (see "Saving with photos that fail" above), sharing one helper.
     Add the limit on how many photos one machine processes at the
     same time: N in config (starting at 2); a photo waits up to 30 s
     (config) for a free slot, then gets "The site is busy — please
     try again in a moment" (see "Memory" above). A slot is freed
     automatically if the page crashes. The Save button says "Saving
     your photos…" while processing. Accept list gains HEIC/HEIF/TIFF/
     AVIF; size limit 25 MB; messages and help texts fixed. LiveView
     upload tests with real files.
     **Changed while implementing (2026-11-09, agreed):** photos are
     processed in a **background task** (`start_async`) after the text
     is saved, not during the button press: LiveView's browser side
     waits at most 30 s for a reply and then reloads the page, which
     would empty the upload box. Shared code:
     `ArtsyNeighborWeb.PhotoUploads`; limiter:
     `ArtsyNeighbor.Images.Limiter` (one slot per photo, freed if the
     page crashes). If a photo is refused, the page stays (a new
     product/artist switches to its edit address), the photo stays in
     the upload box with "Not saved: …", and a red box next to the
     save button repeats it (the flash alone is easy to miss); the
     button's own action (publish, preview, status change, next step)
     isn't carried out. When photos were added and there are now two
     or more, the artist lands on the page with the arrow buttons and
     is asked to check their order. Files refused by the browser check
     (too large, wrong type) or still uploading also keep the page
     open with the red box (before, saving with one would crash the
     page).
     Also (developer's request): the photo sections moved near the top
     of the forms (right after the title; top of the profile form's
     step 2; after Identity in the admin artist form), and photos are
     sent to the server as soon as they are picked (`auto_upload`), so
     the sending happens while the artist fills in the rest.
     Processing still starts at Save (it needs the saved product's id).
     After the code review (2026-11-09): each photo's database row is
     made in the background task right after its files are stored (so
     a closed page can't leave stored files without a row); the flash
     repeats the red box's full reason; the picker, ✕, Previous and
     the stored photos' buttons are disabled while photos are saved;
     Enter on the profile form's steps 1–2 acts like Next; the stored
     photos list is one shared component (`stored_photos`). The
     processing bottleneck itself is NOTES #34.
3. Switch the display sites.
4. NOTES: mark #24 and step b done, add the libvips setup to the step c
   notes; update CLAUDE.md "Key file paths"/conventions (images go through
   `Images`).

## Verification

- Unit tests for `Images`: JPEG, PNG, HEIC, TIFF and AVIF fixtures (small
  ones made with `sips`/libvips), too-small image refused, a non-image renamed to
  `.jpg` refused, EXIF-rotated photo comes out upright, `source.webp` + 3
  sizes written. **GPS test:** a fixture with fake GPS coordinates (made
  from a site image, e.g. position 0,0 — never a real location) goes
  through `process_upload`, and every stored file is checked to have no
  GPS fields (and no EXIF beyond what libvips needs).
  HEIC tests are tagged `:heic` and skipped automatically when the
  libvips in use can't read HEIC; since 2026-11-06 they run on the
  developer's Mac as well as in the server image. A separate test
  checks that, where HEIC isn't supported, the artist gets the plain
  message rather than a crash.
- LiveView upload tests (`file_input` + `render_upload`, real files
  through the real processing): a vendor uploads a JPEG (and a HEIC, where
  supported) and the page then shows the resized image; a too-small photo
  shows the plain-words message. Existing LiveView tests updated for the new
  upload flow; `mix precommit`.
- No permanent Playwright suite in this step (decided 2026-10-28): it
  adds Node + a browser to every test run, and the LiveView tests already
  cover the upload path. Whether to have a small browser suite is a
  question for the test audit (NOTES #19).
- By hand with Playwright on localhost:4002: upload a JPEG and a TIFF as
  a vendor, check product page, artist page tiles, large view; old seed
  images still show; a HEIC from the Mac is processed and shows upright.
- Step c: run the `:heic` tests inside the server's Docker image, then the
  developer uploads from her own iPhone and a HEIC file from her Mac on
  the private deploy.
