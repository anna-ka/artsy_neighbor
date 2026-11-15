# Image storage step c: Tigris on the private preview

*Agreed 2026-11-14* (decisions at the end). Follows
`docs/plans/2026-10-28-image-storage-and-resizing.md` (step b, done in
`3ee135e`). NOTES "Order of work" step 2 c.

## Goal

On the Fly preview, photos survive a deploy and HEIC photos from iPhones
work. Concretely:

1. The server's Docker image has libvips with HEIC support, so the
   `image` library behaves on Fly as it does on the Mac.
2. A new storage backend, `ArtsyNeighbor.Storage.S3`, keeps photos in
   Tigris (S3-compatible storage run by Fly): display sizes in a
   **public** bucket, `source.webp` in a **private** one.
3. Every outside-the-code step (buckets, keys, secrets, check commands,
   how to undo) is written into the runbook `docs/deploy.md` as we go.

Dev and tests keep `Storage.Local`; nothing changes on the Mac unless we
choose dev buckets (question 3 below).

## Facts checked today (2026-11-14)

- `fly storage create` makes a bucket and, when given an app, sets four
  secrets on it: `BUCKET_NAME`, `AWS_ENDPOINT_URL_S3`,
  `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`. The key is printed
  once and can't be fetched again by `fly` (it can in the Tigris
  dashboard: `fly storage dashboard <bucket>`). There is no option to
  rename the secrets, so a **second** bucket for the same app needs
  care (see question 1).
- `--public` makes a public bucket. Public files are served at
  `https://<bucket>.t3.tigrisfiles.io/<key>` (no dots in the bucket
  name). Uploads and other signed calls go to `https://t3.storage.dev`
  (`fly` still sets the older `fly.storage.tigris.dev`; both work, Fly
  recommends switching). New Fly organisations need a verified payment
  method for public buckets — ours has a card for the database.
- Price: $0.02/GB-month; free each month 5 GB, 10 000 uploads/lists,
  100 000 reads; downloads (egress) free; deletes free. The preview will
  stay inside the free part.
- `fly storage destroy <bucket>` deletes a bucket and everything in it
  (asks first; can't be undone).
- Debian trixie (our Docker base) has libvips 8.16 (`libvips-dev` for
  building, `libvips42t64` to run) and the HEVC decoder plugin
  `libheif-plugin-libde265`. The Mac has 8.18; `vix` 0.42 is fine with
  both.
- Docker is installed on the Mac, so the HEIC tests can run inside the
  build image before anything is deployed.

## Steps (three commits)

### c1. libvips + HEIC on the server (code only, no accounts)

- `Dockerfile`, build stage: `apt-get install libvips-dev pkg-config`,
  and `ENV VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS` before
  `mix deps.compile`.
- Runtime stage: `libvips42t64 libheif-plugin-libde265`.
- Check locally: build the builder stage with Docker and run the
  `:heic` image tests inside it.
- A look-only check on the live machine,
  `ArtsyNeighbor.Release.image_support/0` (libvips version, can it read
  HEIC), run with `fly ssh console -C "/app/bin/artsy_neighbor eval ..."`.
  Into the runbook.
- Deploy; the developer uploads an iPhone photo and a HEIC from the Mac
  (still stored on the machine's disk, so lost on the next deploy — as
  today).
- **Measure memory on Fly** (NOTES step 2c item): `fly machine status` /
  Fly's metrics page while uploading a 12 MP and a 48 MP photo. Decide
  512 MB vs 1 GB and N afterwards, together.

Small and separate on purpose: if the image grows or breaks, we know why.

### c2. `Storage.S3` (code only, no accounts)

- Deps: `ex_aws` + `ex_aws_s3` (the library Tigris documents for
  Elixir), using `req` (already in the app) as its HTTP client if
  ex_aws's Req adapter works for us, otherwise its default `hackney`.
  Alternative: `req_s3`, smaller but less documented.
- `Storage.S3` implements the four callbacks:
  - `put/3` → upload to the public or private bucket, with
    `Content-Type: image/webp` and, for public files,
    `Cache-Control: public, max-age=31536000, immutable` (safe: every
    photo has its own UUID folder and is never changed in place).
  - `url/1` → `<public_base_url>/<key>`, where `public_base_url` is
    config (`https://<bucket>.t3.tigrisfiles.io` now; a custom domain
    like `photos.artsyneighbor.ca` later needs only a config change).
  - `read/2` → download.
  - `delete_prefix/1` → list everything under `prefix <> "/"` in both
    buckets and delete it (the UUID safety check in `Storage` stays).
- Config: `config/runtime.exs` switches prod to `Storage.S3` and reads
  the bucket names, endpoint and keys from environment variables;
  refuses to start if one is missing (like the site password).
- Tests: see question 3.

### c3. Buckets on Fly + first deploy with Tigris (outside the code)

Done one command at a time, each explained first; the developer runs
anything that touches her accounts. Written into a new `docs/deploy.md`
section as we go (see question 2):

1. Create the public bucket, the private bucket (names in question 1).
2. Give the app a key that can use both (question 1).
3. Point `AWS_ENDPOINT_URL_S3` at `https://t3.storage.dev`; set the
   bucket-name and public-URL settings (not secret).
4. Look-only checks: `fly secrets list` (names only, never values),
   `fly storage list`, the Tigris dashboard.
5. Deploy. Upload, view, reorder and delete a product photo and a
   profile photo; check in the dashboard that `source.webp` is in the
   private bucket and that its URL is refused from outside.
6. Undo path: switch `Storage` back to `Local` by config, or
   `fly storage destroy`.

Old rows on the preview that point at files lost in earlier deploys
stay broken; the preview's data gets refilled by the seed script
(NOTES step 2 (ii)), which comes next and uploads seed images through
`Images` into Tigris.

## Left for later (into NOTES, not this step)

- Backups of the buckets (NOTES says "a scheduled copy to a second
  place"): for now a runbook command to copy both buckets to the Mac;
  a schedule before testers.
- Clean-up of folders no row points to (NOTES #34): easy to list a
  bucket now; do it with the seed script or later.
- Custom domain for photos (with the site's domain, step 5).
- Removing public sizes when a product is hard-deleted (open since
  step b).

## Decisions (2026-11-14)

1. Two buckets, one key, as recommended below.
2. A separate runbook, `docs/tigris.md`, linked from `docs/deploy.md`
   (from §1 "What runs where" and from the rebuild steps in §4).
3. Fake S3 in tests (a), no dev buckets.
4. All three parts written first, then **one deploy**. To keep the
   advantage of going step by step: three separate commits, and c1's
   HEIC tests run in Docker on the Mac before the deploy, so a problem
   with libvips shows up before Tigris is involved.

## Open questions for the developer (as asked)

1. **Two buckets, one key.** Recommended: create the public bucket with
   `fly storage create --public -a $APP` (sets the four secrets for
   us), create the private one without `-a`, then in the Tigris
   dashboard give the *same* key access to the private bucket too.
   No key ever has to be copied by hand. (Alternative: one bucket with
   per-file "public" markings — fewer pieces, but one forgotten setting
   publishes a `source.webp`; I'd rather keep the separation we planned.)
   Names: e.g. `an-preview-photos` and `an-preview-originals` (must be
   unique across all of Tigris; no dots).
2. **Runbook:** a new section in `docs/deploy.md` (e.g. "§4.7 Photo
   storage") so a rebuild from scratch is one document — recommended —
   or a separate `docs/tigris.md`.
3. **Testing `Storage.S3`:** (a) tests with a fake S3 (ex_aws lets us
   swap its HTTP client in tests), always run, no accounts — plus the
   manual checks on the preview in c3. Recommended. Or (b) also a pair
   of small dev buckets so `Storage.S3` can be tried from the Mac and an
   opt-in `:tigris` test runs against them — more realistic, but keys
   on the Mac (in a gitignored file) and two more buckets to look after.
4. **Order:** c1 first and deployed on its own (recommended), or all
   three together.
