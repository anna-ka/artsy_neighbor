# Photo storage on Tigris (private preview)

The runbook for where the preview keeps uploaded photos: what was set
up, the exact commands, how to look at it, and how to undo it. A
companion to `docs/deploy.md` (the app and database); read that first.
Plan and reasons: `docs/plans/2026-11-14-tigris-image-storage.md`.

**Status:** set up 2026-11-15 (release v5), following §3 step by
step and correcting it along the way. All checks pass except deleting
(§3.5 check 6: a deleted photo's files stay; `NOTES.md` #39).

Never put a key or secret in this file. They live in Fly (and the
secret access key in the developer's Passwords app), nowhere in the
repo.

---

## 1. What runs where

```
Browser ──▶ Fly proxy ──▶ app Machine ──signs in with its key──▶ Tigris
   │                        (uploads, deletes, reads originals)   ├─ $APP-photos     (public)
   │                                                              └─ $APP-originals  (private)
   └──────── loads photos directly ──────────────────────────────▶ $APP-photos only
             https://$APP-photos.t3.tigrisfiles.io/<key>
```

**Tigris** is object storage (S3-compatible) that Fly resells: no
separate account, billed on the Fly bill. A **bucket** is a named
folder of files there. A **key** (access key id + secret access key)
is the username/password our app uses to sign in to Tigris.

| Piece | Name | Notes |
|---|---|---|
| Public bucket | `$APP-photos` | display sizes `thumb/medium/large.webp`; anyone with a file's address can load it |
| Private bucket | `$APP-originals` | `source.webp` per photo; only readable with the key |
| Key | made by `fly storage create` for the public bucket; its name ends in `_photos` | Read-Write on both buckets (§3.3) |
| API address | `https://t3.storage.dev` | where the app sends uploads (signed) |
| Public address | `https://$APP-photos.t3.tigrisfiles.io` | where browsers load photos from |

**In the app:** `ArtsyNeighbor.Storage.S3` (`lib/artsy_neighbor/storage/s3.ex`),
switched on in `config/runtime.exs` for production only. Dev and tests
keep files on the Mac (`Storage.Local`).

**Cost:** the preview stays inside Tigris' monthly free allowance (5 GB
stored, 10 000 uploads/lists, 100 000 reads; downloads free). Beyond
that, $0.02 per GB per month. Checked 2026-11-14.

## 2. Known limitations

- **Photos skip the site password.** Pages still need it, but a
  photo's address works for anyone who has it. Addresses contain a
  random code (`products/12/0b6c5e1a-…/medium.webp`), so they can't be
  guessed; someone would have to be sent one. `source.webp` is in the
  private bucket and never reachable this way.
- **No backup of the buckets yet.** A manual copy to the Mac and a
  schedule come later (`NOTES.md`, step 2c).
- **Photos uploaded before Tigris are gone** (they were on the
  Machine's disk). Their database rows still point at them and show
  broken pictures until the preview's data is refilled (seed script,
  `NOTES.md` step 2 (ii)).

---

## 3. Setting it up

Order matters: **the new code refuses to start without these
settings** (`config/runtime.exs` raises, like for the site password),
so the buckets and secrets come first, the deploy last.

In the terminal, in the repo folder, set `$APP` first:

```
APP=an-preview-g3ukxp
```

### 3.1 Check the HEIC support in the new image (no cost, no account)

Done on the Mac with Docker before anything else, see §5.

### 3.2 The public bucket (sets the app's secrets)

```
fly storage create --public --name $APP-photos --app $APP
```

| Part | Why |
|---|---|
| `--public` | files can be loaded by browsers without signing in |
| `--name $APP-photos` | bucket names are unique across all of Tigris; ours starts with the app's random name |
| `--app $APP` | also sets five secrets on the app: `BUCKET_NAME`, `AWS_ENDPOINT_URL_S3`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` (value `auto`, Tigris' name for "global"; we don't read it: `runtime.exs` sets the same `auto` itself) |

*Done 2026-11-15 (flyctl 0.5.10, flags unchanged).* It asked no
questions. Afterwards it restarted the app Machine to load the new
secrets ("Updating existing machines ... update succeeded"); harmless,
because the code running then ignored them.

It prints the key **once**. Save the *secret access key* in Passwords
(title e.g. "Tigris key an-preview"); it's needed later for copying
the buckets to the Mac. Don't paste it anywhere else. If it's lost,
the Tigris dashboard can make a new one (§4).

New Fly organisations need a verified payment method for public
buckets; ours has a card on file for the database.

### 3.3 The private bucket (no secrets)

**Run this from another folder** (e.g. `cd ~` first). Inside the repo,
`fly` reads `fly.toml` and would connect this private bucket to the
app, setting the four secrets again: `BUCKET_NAME` would then name the
private bucket (display photos would go where browsers can't load
them) and the app's key would be replaced by one that can't use the
public bucket. We want the app's secrets to keep pointing at the
public bucket from §3.2.

```
cd ~
fly storage create --name $APP-originals --org personal
cd -
```

(`cd -` goes back to the previous folder.) No `--public`: private is
the default. It prints a second key; we don't use it (and can delete
it in the dashboard), so it needn't be saved.

*Done 2026-11-15.* As hoped, it didn't touch the app: no restart, no
new release, and `fly secrets list` showed the same digests (a
fingerprint of each value) as before.

Then give **the app's key** (from §3.2) access to this bucket too, in
the Tigris dashboard:

```
fly storage dashboard $APP-photos
```

In the dashboard (done 2026-11-15):

1. **Access Keys** (left side panel).
2. The key whose name ends in **`_photos`**: that's the app's key from
   §3.2. Check that its access key ID matches the one in Passwords.
   (The key from §3.3 ends in `_originals`.)
3. **Bucket Roles** tab. Both buckets are listed. Before this step
   `$APP-photos` showed only "Select option", even though Fly had made
   the key for that bucket.
4. Set **both** buckets to **Read-Write**, and save.

Why Read-Write, not Editor: the app only uploads, reads, lists and
deletes files (`Storage.S3`). It sets no per-file "public" flag,
because the public bucket is public as a whole. Editor would most
likely add rights to change the buckets' own settings, which the app
doesn't need; a key that leaked couldn't, say, make the originals
public. If uploads fail with "access denied" at §3.5, try Editor.

Then delete the unused `_originals` key: Access Keys → the key whose
access key ID does *not* match the one in Passwords → delete. Done
2026-11-15; only the `_photos` key is left.

### 3.4 The settings we set ourselves

```
fly secrets set --stage PRIVATE_BUCKET_NAME=$APP-originals AWS_ENDPOINT_URL_S3=https://t3.storage.dev --app $APP
```

- `PRIVATE_BUCKET_NAME`: not secret, but kept with the others.
- `AWS_ENDPOINT_URL_S3`: `fly` sets the older `fly.storage.tigris.dev`;
  Fly recommends `t3.storage.dev` for new code. Both reach the same
  buckets.
- `--stage`: just store them; they take effect at the next deploy
  instead of restarting the app now.

*Done 2026-11-15.* It printed "Secrets have been staged, but not set
on VMs. Deploy or update machines in this app for the secrets to take
effect." No restart, no new release. `fly secrets list` then marks the
two with `*` and status `Staged` until the deploy.

Check (names only, never values):

```
fly secrets list
fly storage list
```

`fly secrets list` should show `AWS_ACCESS_KEY_ID`,
`AWS_ENDPOINT_URL_S3`, `AWS_SECRET_ACCESS_KEY`, `BUCKET_NAME`,
`PRIVATE_BUCKET_NAME`, plus the earlier ones (`DATABASE_URL`,
`SECRET_KEY_BASE`, `SITE_USERNAME`, `SITE_PASSWORD`).

### 3.5 Deploy and check

```
fly deploy --ha=false
```

If the app doesn't start, `fly logs` shows which variable is missing
("environment variable ... is missing").

*Done 2026-11-15 (release v5).* The build took several minutes
(libvips). The migration ran first on a short-lived Machine, as
usual. The app Machine was asleep, so the deploy only updated it; it
started at the first visit (`curl` → `401` from the site password
means it's up), and the logs showed "Running ArtsyNeighborWeb.Endpoint"
with no missing settings.

Then:

1. **HEIC on the live machine:**
   ```
   fly ssh console -C "/app/bin/artsy_neighbor eval 'ArtsyNeighbor.Release.image_support()'"
   ```
   Expect `HEIC decode: OK`. *2026-11-15: `libvips version: 8.16.1`,
   `HEIC decode: OK (998 bytes of WebP)`; the `sctp` warning before it
   is harmless.*
2. **Upload** a product photo (an iPhone photo, and a HEIC file from
   the Mac) and a profile photo. They show on the page; right-click a
   photo → "Copy Image Address": it starts with
   `https://$APP-photos.t3.tigrisfiles.io/`.
3. **The public file is cacheable:** `curl -I <that address>` shows
   `200` and `cache-control: public, max-age=31536000, immutable`.
4. **The private file is not reachable:** in the address, replace
   `$APP-photos` with `$APP-originals` and `medium.webp` with
   `source.webp`; `curl -I` on it must **not** show `200`.

   *Checks 2–4 done 2026-11-15* with a phone photo
   (`.../products/5/<uuid>/large.webp`): the address starts with the
   public bucket's; `large`/`medium`/`thumb` give `200`, `image/webp`
   (716 / 356 / 109 KB) and the year-long `cache-control`;
   `source.webp` gives `404` in the public bucket; the private
   bucket's `.t3.tigrisfiles.io` address doesn't even connect (a
   private bucket has no public address), and the API address
   `https://$APP-originals.t3.storage.dev/<key>` without the key gives
   `403 Forbidden`.
5. **Both buckets have the files:** the dashboard (§4) shows the photo's
   folder with three sizes in `$APP-photos` and `source.webp` in
   `$APP-originals`. *Done 2026-11-15:* the phone photo's folder is in
   both buckets, as expected.
6. **Delete** the photo in the app; its folder disappears from both
   buckets. *2026-11-15: **fails, as the code stands.** Deleting the
   second photo of product 6 removed it from the site with no error,
   but its files stayed in both buckets (not a browser cache: the app
   only deletes the database row; the step b plan had left deleting
   files for later). To be fixed: `NOTES.md` #39. Re-run this check
   after the fix.*
7. **Memory:** while uploading, watch the Machine's memory on the
   app's Metrics page (`fly dashboard` → Metrics). Write the peak here
   and in `NOTES.md` step 2c; decide 512 MB vs 1 GB together.
   *2026-11-15:* on **512 MB**, saving a product with two iPhone photos
   from the phone got the app killed ("Out of memory: Killed process
   ... beam.smp" in `fly logs`, at ~457 MB; the phone showed "no
   internet connection"). One photo worked. Moved to **1 GB**
   (`fly.toml` + `fly scale memory 1024 --app $APP`). Then two photos
   worked. The "Firecracker Memory Usage" graph: `mem_total` is the
   Machine's size (~477 MB on 512 MB, ~954 MB on 1 GB); `mem_used` was
   ~250–280 MB at rest before, ~383 MB at rest after the restart, and
   showed **no bump** during the two-photo save (~7:18 pm local). Its
   samples are too far apart to catch a peak of a second or two, so
   it can't tell us the processing peak; that needs log lines.

## 4. Look-only commands

| Command | Shows |
|---|---|
| `fly storage list` | the buckets in the organisation |
| `fly storage dashboard $APP-photos` | opens Tigris' web page: files, keys, usage |
| `fly secrets list` | secret names (never values) |
| `curl -I <photo address>` | whether a photo is reachable, and its headers |

## 5. HEIC check with Docker on the Mac

Builds the same image Fly builds, then runs the check inside it.
Docker Desktop must be running.

```
docker build -t artsy-neighbor-check .
docker run --rm \
  -e DATABASE_URL=ecto://x:x@localhost/x -e SECRET_KEY_BASE=$(printf 'x%.0s' {1..64}) \
  -e SITE_USERNAME=x -e SITE_PASSWORD=x \
  -e BUCKET_NAME=x -e PRIVATE_BUCKET_NAME=x -e AWS_ENDPOINT_URL_S3=https://example.com \
  -e AWS_ACCESS_KEY_ID=x -e AWS_SECRET_ACCESS_KEY=x \
  artsy-neighbor-check /app/bin/artsy_neighbor eval 'ArtsyNeighbor.Release.image_support()'
```

The `-e` values are dummies: the release only checks that they exist;
the check uses neither the database nor Tigris. The Mac's chip (ARM)
differs from Fly's (x86), but the Debian packages are the same.
Afterwards `docker image rm artsy-neighbor-check` frees the space.

## 6. Undoing it

- **Back to the old code:** `fly releases --image`, then
  `fly deploy --image <earlier image>` (deploy.md §6). The old code
  ignores the Tigris secrets; photos go to the Machine's disk again.
- **Remove a bucket and everything in it** (asks first; can't be
  undone): `fly storage destroy $APP-photos` (and `$APP-originals`).
  Then `fly secrets unset BUCKET_NAME PRIVATE_BUCKET_NAME
  AWS_ENDPOINT_URL_S3 AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY`.
- **Tearing down the whole preview** (deploy.md §8): destroy both
  buckets too (not yet checked whether `fly apps destroy` removes
  them; `fly storage list` shows what's left).
