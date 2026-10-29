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
- **Mac (dev): the `image` library's ready-made libvips — no HEIC.**
  `brew install vips` was tried and isn't practical: on macOS 14 Homebrew
  no longer has ready-made packages, so it compiles ~110 packages from
  source (hours, and it stopped with an error). The developer prefers not
  to upgrade macOS just now. In dev, a HEIC upload gets a plain message
  instead of being processed; everything else works.
- **Switching dev to HEIC later** (e.g. after a macOS upgrade): `brew
  install vips`, set `VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS`,
  `mix deps.clean vix && mix deps.get && mix compile`. No code changes.
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
  holding `original.<ext>`, `large.webp` (≤2500px long side), `medium.webp`
  (≤1600px), `thumb.webp` (≤600px).

**New modules** (`lib/artsy_neighbor/`):
- `Images` — the one public entry point.
  - `Images.process_upload(tmp_path, client_name, folder)` → checks it's a
    real image (opens it with libvips; extension alone isn't trusted),
    refuses if the long side < 800px with the plain-words message from
    NOTES #24, auto-rotates using the photo's orientation tag, strips
    metadata (GPS location from phones), writes original + 3 sizes,
    returns `{:ok, key}` or `{:error, message}`.
  - `Images.url(path_or_key, size)` → old `/...` path unchanged; a key →
    `Storage.url("<key>/<size>.webp")`.
- `Storage` — behaviour with `put(local_file, key)`, `url(key)`,
  `delete_prefix(key)`; backend chosen in config.
  - `Storage.Local` — writes under `priv/static/uploads/<key>`, URL
    `/uploads/<key>` (dev). Test env points it at a tmp folder.
  - (`Storage.S3` comes in step c.)

**Forms** (vendor product, vendor profile, admin product, admin artist):
replace the copy-a-file blocks (`File.cp!` sites, e.g.
`vendor_live/product_form.ex:207-225`, `:259-273`) with
`Images.process_upload/3`; show its error messages next to the upload.
Raise `max_file_size` from 5 MB to 25 MB (phone photos are big; we shrink
them anyway) and fix the mismatched "max 3 MB" message. Product images
stored under `products/<product_id>/`, artist images under
`artists/<artist_id>/`.

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

0. Spike: add `{:image, ...}` (ready-made libvips), confirm it opens JPEG,
   PNG, WebP, and a TIFF and an AVIF made from
   `~/Code/artsy-neighbor-design/IMG_6457.HEIC` (with `sips`), and that
   HEIC itself fails with a clear error we can turn into a plain message.
   If TIFF or AVIF fails, report and drop that one. HEIC on the server is
   confirmed in step c.
1. `Storage` + `Storage.Local` + `Images` with tests.
2. Switch the four upload forms.
3. Switch the display sites.
4. NOTES: mark #24 and step b done, add the libvips setup to the step c
   notes; update CLAUDE.md "Key file paths"/conventions (images go through
   `Images`).

## Verification

- Unit tests for `Images`: JPEG, PNG, HEIC, TIFF and AVIF fixtures (small
  ones made with `sips`/libvips), too-small image refused, a non-image renamed to
  `.jpg` refused, EXIF-rotated photo comes out upright, 3 sizes written.
  HEIC tests are tagged `:heic` and skipped automatically when the
  libvips in use can't read HEIC (as on the developer's Mac); they run
  wherever it can (the server image, a later dev setup). A separate test
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
  images still show; a HEIC shows the plain message.
- Step c: run the `:heic` tests inside the server's Docker image, then the
  developer uploads from her own iPhone and a HEIC file from her Mac on
  the private deploy.
