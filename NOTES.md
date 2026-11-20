# Notes / Backlog

A running, lightweight list of things to come back to — bugs, deferred
work, design decisions made but not yet built. Not a spec, not a plan doc
(see `docs/plans/` for those) — just a shared punch list so nothing gets
lost between sessions. Delete a bullet once it's actually done or no
longer relevant; no need to keep history here (git history covers that).

## Order of work (agreed 2026-09-25)

Guiding goal: put a version in front of a few invited testers (friends,
family, local artists who may become real users). Their goodwill is
limited — they'll likely look carefully once — so what they see should be
close to the real thing, and admin support tools must exist so their
mistakes can be cleaned up quickly. Debt is paid as we go (clean up the
area being worked on), not in big dedicated passes — except formatting,
which is mechanical and done once, up front.

0. **Housekeeping** — done 2026-09-25 (`mix format` sweep, docstring
   trim, compose-box bug).
1. **Design system + branding** — mockups → pick a direction → DaisyUI
   theme, layout/nav (incl. the small-screen nav issue), shared
   components, LocalPalette name (#14), a favicon (`/images/favicon.ico`
   currently 404s on every page); restyle only the key public pages
   (home, artist page, store). Later pages get the new look as they are
   built or reworked. Consider a throwaway branch for trying directions.
   Agreed approach (2026-09-25):
   - Developer collects reference screenshots, with a line on what she
     likes about each (colours, fonts, artwork layout, spaciousness).
   - Claude builds 2–3 static mockups of one key page in different
     directions; the developer picks one.
   - The chosen direction becomes a DaisyUI theme plus shared
     components in `core_components.ex`.
   - Then restyle page by page, with Playwright screenshots of each
     result for review.
   - Minimal JS; DaisyUI + Tailwind only — keep the site lightweight.
   - Logo: the developer's daughter is designing it; the favicon comes
     from it.
   - Plan doc / design brief: `docs/plans/2026-09-28-design-system.md`.
   - **Audience (guiding principle):** launch city is Victoria, BC, with
     an older population. Many artists will be over 60, a good share
     over 50, likely most over 40. Design for intuitive and easy over
     flashy: comfortable text size and contrast, large click targets,
     buttons labelled with words (not icon-only), nothing that only
     works on hover, familiar patterns, few steps, clear confirmations.
2. **Private deployment (just the developer)** — Fly.io, Tigris for image
   storage (#17, #18), basic-auth password on the whole site. Done step
   by step with a written runbook in `docs/deploy.md`; finish by tearing
   the app down and rebuilding it from the runbook. Add a GitHub Actions
   workflow running `mix precommit` around this time. No continuous
   deployment — `fly deploy` stays manual.
   *Changed 2026-10-29:* a plain Fly deploy now comes before image
   steps b and c (uploads on the deployed site are lost on each deploy
   until c is done; fine while only the developer uses it). Done so far:
   release files (`mix phx.gen.release --docker`), the site-wide
   password (`ArtsyNeighborWeb.Plugs.SitePassword`, required in prod by
   `runtime.exs`), and patch updates of Phoenix, LiveView, Bandit and
   Plug. Then the full update, also 2026-10-29: all libraries at their
   latest, LiveView 1.2, Elixir 1.20.4 and Erlang 29.1.2 (Homebrew on
   the Mac; the same versions in the Dockerfile). Deployed 2026-11-02
   with an unmanaged Fly Postgres 17 (chosen 2026-10-28 for cost);
   runbook written 2026-11-03; first `pg_dump` backup taken and
   restored 2026-11-03.
   Region: San Jose (`sjc`), chosen 2026-10-30. Fly no longer offers
   Seattle; Toronto (`yyz`) would keep data in Canada but is about
   twice as far (~60–80 ms per round trip vs ~25–40), and payments will
   go through the US anyway. The database must be in the same region
   as the app.
   **Done 2026-11-04:** a practice teardown + rebuild from the runbook,
   still on Postgres 17 (new app `an-preview-g3ukxp`, the old
   `an-preview-wm0upn` destroyed). Also the Mac backup: no second
   drive; the 2 TB Kingston drive reformatted as APFS with a `Backup`
   volume (Carbon Copy Cloner, home folder) and a `TimeMachine`
   volume, plus a checked `pg_dump` of the dev database.
   **Next, in this order (agreed 2026-11-03, updated 2026-11-04)**, one
   change at a time so a problem is easy to trace back:
   1. ~~Update `ecto` and `phoenix_html` for the two security
      advisories, `mix precommit`, deploy.~~ **Done 2026-11-04**
      (`52f8ce1`: `ecto` 3.14.3, `phoenix_html` 4.4.0; deployed to the
      preview, the first "deploying a change" run, all good).
   2. ~~macOS upgrade from Sonoma 14.7.7, after a fresh CCC copy that
      has been spot-checked.~~ **Done 2026-11-05** (to macOS 27.2,
      ahead of image storage after all — developer's choice).
   3. Check the dev setup still works (Homebrew/Xcode command-line
      tools, `mix phx.server`, `mix test`, Postgres.app).
      **2026-11-06:** `mix test` (781 pass), `mix phx.server`,
      Postgres.app 17 and the dev data all fine. One breakage, fixed:
      the downloaded Tailwind binary has an invalid code signature,
      which macOS 27 refuses (killed on start, exit 137; see Known
      limitations). Also done the same day: Xcode command-line tools
      updated (clang 21), `pkgconf` reinstalled, `node` 24.5 → 26.13,
      old `icu4c@77` removed, and the two compromised root
      certificates removed from `/etc/ssl/cert.pem` with Homebrew's
      script (tested first: GitHub, Fly and Hex still connect).
      `brew doctor` is clean. Homebrew installs ready-made packages
      again: `brew install vips` (8.18.7, with libheif 1.23.7 +
      libde265) worked in minutes, and it reads HEIC (tested with a
      file made by `sips`). So the Mac can use system libvips with
      HEIC like the server — the image plan's "Mac (dev): no HEIC"
      section needs updating at the start of step b.
   4. Postgres.app 17 → 18 on the Mac (see Tech debt), restoring the
      dev data.
   5. Tear down the Fly preview again and rebuild it, this time with
      the new database created directly on Postgres 18.
   **Changed 2026-11-04 (developer's choice):** before items 2–5, do
   (i) image storage b–c below (plan:
   `docs/plans/2026-10-28-image-storage-and-resizing.md`; Tigris is
   c), then (ii) a script that fills the Fly preview database with the
   seed data. Points to settle for (ii): `seeds.exs` starts with
   `Repo.delete_all(...)` on every table, so it would also wipe the
   preview's admin account; a release has no `mix`, so it has to run
   another way (e.g. `bin/artsy_neighbor eval` or a function in
   `ArtsyNeighbor.Release`); and the seed images must go into Tigris,
   which is why (i) comes first.
   Until step 5, the Fly database stays on Postgres 17. Meanwhile, work
   that doesn't touch the Mac's setup (e.g. planning image storage b–c,
   the Neon question).
   Image storage was planned to come first (agreed 2026-10-28, see #17),
   in three commits:
   - **a. Cleanup** — done 2026-10-28: all of `uploads/` gitignored and
     untracked (files kept on disk); the placeholder images and
     `logo.svg` moved into `images/site/`; unused drafts moved out of
     the repo to `~/Code/artsy-neighbor-design/`.
   - **b. `Storage` module + automatic resizing (#24)** — **done
     2026-11-09** (commits `b565be3`, `a935172`, `60a59b7`, `973fa3d`
     and the display-sites commit), dev still on local disk. The
     database's `path` column holds either an old-style web path
     starting with `/` (shown as-is, so no data conversion was needed)
     or a key (`products/<product id>/<random id>`, a folder holding
     `source.webp` + `large`/`medium`/`thumb.webp`); pages always show
     photos through `Images.url(path, size)`. A large private copy
     (`source.webp`, ≤4096px) is kept so sizes can be regenerated
     later (and image embeddings recomputed) — with all metadata
     stripped, never the raw upload, since phone photos carry GPS
     location. Also came with it: product `:draft` status, "needs a
     photo" rules, background photo processing with a limit of N at a
     time. Details and decisions: the plan doc. Left over: the missing
     `wall_art.jpg` in dev data (fix by hand; the sample data now gives
     "Other Art" no picture, so the placeholder shows).
   - **c. Tigris** (created from Fly with `fly storage create`, no
     separate account) as the first part of the deploy, plus backups:
     a scheduled copy of the bucket to a second place, and database
     backups, both in the runbook. Before signing up for Fly: decide
     whether to use a project email address rather than a personal one
     for service accounts (Fly, domain, later Stripe).
     - **libvips on the server** (added 2026-11-09). The `image`
       library needs libvips with HEIC support (libheif + an HEVC
       decoder). On the Mac it is Homebrew's (`brew install vips` plus
       `VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS`, see README).
       The `Dockerfile` doesn't install it yet: the build stage needs
       libvips' development package and the same setting before `vix`
       compiles, the runtime stage the libvips library. Check that
       `test/artsy_neighbor/image_setup_test.exs` (decodes a HEIC)
       passes in that image, or iPhone photos get the "can't read
       HEIC" message on the real site.
     - **Storage.S3** (Tigris): two buckets, public for the display
       sizes and private for `source.webp` (see the plan's "Public vs
       private storage").
     - **Reconsider image-processing memory before inviting testers**
       (added 2026-11-09). Processing a photo needs a lot of memory
       (measured on the Mac 2026-11-09: ~370 MB peak for a 12 MP photo,
       ~520 MB for the worst case still allowed, a 52 MP 16-bit TIFF),
       and the Fly machine has 512 MB. Step b adds an adjustable limit
       of N photos processed at a time per machine (config, starting at
       N = 2). Measure on the real server, then decide together: the
       machine's memory (1 GB is ~$3/month more than 512 MB) and N.
       One-at-a-time was rejected: it becomes a hidden queue when many
       artists upload at once.
       **2026-11-15, first real test:** uploading two iPhone photos at
       once from the phone got the app killed for lack of memory on the
       512 MB machine ("Out of memory: Killed process ... beam.smp"; the
       phone showed "no internet connection"). One photo worked.
       Developer's choice: 1 GB machine (`fly.toml`), N stays 2, no swap,
       so that running out of memory stays visible in the logs rather
       than turning into slowness. On 1 GB two photos worked. Fly's
       memory graph is too coarse to show the processing peak (no bump
       during the save; ~383 MB "used" at rest; details in
       `docs/tigris.md` §3.5). Saving also felt slow (a few seconds).
       **2026-11-16, measured with the timing log lines** (table in
       `docs/tigris.md` §3.5 check 7): a 12 MP phone photo takes ~5 s
       to process on Fly and <1 s to store; a 9 MP painting 4.6 s, so
       the time barely depends on the photo's size (making the three
       display sizes costs about the same for any big photo, and both
       fit under 4096px, so `source.webp` is encoded at full size, q95).
       Photos of one save go one after another: 2 photos ~11 s, 5 ~30 s.
       Memory: ~470 MB peak for one photo, ~310 MB at rest, so 1 GB is
       enough for N = 2. The iPhone sent JPEG, not HEIC. To try with
       step 3 (browser shrinking), measuring each on the Mac first:
       the WebP encoder's `effort` setting (lower = faster, slightly
       bigger files), and making the three display sizes in one pass
       instead of re-reading `source.webp` three times. A more
       fundamental fix is still needed before testers (#34).
     - **Next, in this order (agreed 2026-11-16):**
       1. ~~Photo timing logs and #39 (deleting a photo deletes its
          files)~~ — **done 2026-11-16** (`d00cb11`), deployed; check 6
          passed and timings measured on Fly (above).
       2. The script that fills the preview database (item (ii)
          above), so the developer's daughter (illustrator, helping
          with looks and logo) can see the site with content.
          **Done: run on Fly 2026-11-17** (`fcb57c7`, plus `db38e13`:
          a hand-made "Paintings" with another slug clashed on the
          unique name, so categories are now skipped by slug or name).
          All 13 artists, 81 works and 105 photos in about 10 minutes;
          the studio got its own login (`anna.demo@example.com`, the
          admin already has an artist profile). Written 2026-11-16
          (after a code
          review: goes in through the site's own activate/publish
          rules, one failing artist is removed again and doesn't stop
          the rest; plus `Release.remove_sample_data/0` and
          `Release.check_before_launch/0`):
          `ArtsyNeighbor.SampleData` + data files in
          `priv/repo/sample_data/`; on Fly
          `Release.add_sample_data/0` via `rpc` (`docs/deploy.md`
          §5.1). Add-only; all 13 artists (the six original seed
          artists got generated initials avatars: their old photos
          were dev-only and too small),
          photos through `Images.process_upload/3` into Tigris, the
          developer's studio linked to the admin account. `seeds.exs`
          and `demo_data.exs` now use the same module, so on the Mac
          their photos go into storage too. Password `DevPassword1!`
          kept (developer's choice 2026-11-16: private repo + site
          password; audit item "Seed accounts have a published
          password"), so the sample accounts must go before testers
          (`docs/deploy.md` §10: `remove_sample_data`, then
          `check_before_launch`). The developer plans to start the
          preview's database over before testers anyway.
       3. **Photo speed** (#34; order agreed 2026-11-16 after measuring
          on the Mac where the time goes: for a 12 MP photo, decoding
          47 ms, shrinking to the three sizes 23 ms, encoding
          `source.webp` at full size q95 988 ms, encoding the three
          display sizes 490 ms, i.e. ~95% is WebP encoding; Fly is ~3×
          slower). **Seen on Fly 2026-11-17 (the sample-data run, 105
          photos of 1–2.5 MP in a row):** for the first ~80 s each photo
          took ~1 s to process, then 5–17 s for the rest of the 10
          minutes, with no wait in the limiter and memory under 420 MB.
          Very likely Fly's shared-CPU limit: a shared CPU may run at
          full speed in bursts, and is slowed down to a small share of
          a core once the burst allowance is used up (to check: the
          app's CPU panels in the Fly dashboard Metrics around 19:10
          UTC). So measure a *series* of photos, not one (a vendor
          adding 20 at once), and see whether 3a's savings keep a
          series within the burst; otherwise a bigger CPU (cost) or
          a queue that spreads the work out.
          *Found 2026-11-17:* the sample photos are small (almost all
          0.6–1.4 MP, 1200 px wide), so that run measured about a
          twelfth of a phone photo's pixels. Fly's numbers (docs.fly.io
          "CPU performance"): a shared CPU is guaranteed 6.25% of a core
          (5 ms in every 80 ms); unused time builds up a burst balance
          of at most 500 s at full speed, and a new or restarted
          Machine starts with only 5 s, which fits the slowdown right
          after a deploy. The preview's `fly.toml` stops the Machine
          when idle (`auto_stop_machines = 'stop'`,
          `min_machines_running = 0`), so it probably starts each visit
          with that 5 s too; the real site should keep one Machine
          running so the balance can build up (an idle Machine earns
          it back in about 2 hours). Prices (US, per month, billed per second):
          shared-cpu-1x 1 GB $6.70 (now), shared-cpu-2x 2 GB $13.39,
          performance-1x 2 GB $33 (a full core, never slowed down),
          performance-2x 4 GB $66.
          **Measuring:** `Release.time_photos/1`
          (`ArtsyNeighbor.Images.Timing`) processes 20 sample photos
          enlarged to phone size (4032 px) in a row, like real uploads,
          prints wall time and CPU time per photo, and deletes them
          again. CPU time doesn't depend on Fly slowing the CPU, so it's
          the number to compare before/after and to plan capacity
          with. **Before 3a, on the Mac: 1.48 s CPU per photo** (about
          2,400 photos an hour per full core). **Fly before 3a
          (2026-11-17, 17:12 Vancouver time):** 8 photos at full speed, ~3.9 s
          CPU each (2.6× the Mac; wall = CPU + 0.2–0.8 s storing),
          then the burst ran out (after ~45 s of CPU, 13 s of it the
          run's preparation) and photos 9–20 took 45–110 s each, about
          7% of a core. 16.5 minutes for 20 photos, peak memory 464 MB.
          Correction: the slowed-down photos showed ~6.5 s CPU, not
          3.9, so CPU time is only fair for full-speed photos; the tool
          now reports those separately. At 3.9 s: our shared CPU
          sustains ~60 photos an hour, a full burst ~130 photos, one
          performance core ~900; Victoria's 20 artists × 20 photos in
          an hour needs ~400. While slowed down, a photo takes over a
          minute. One artist's photos go through the limiter one after
          another (one slot at a time), so they never wait on each
          other; but with 2 slots and a 30 s wait, a *third* artist
          saving photos while two others are being processed would
          get "site is busy".
          **3a written 2026-11-17, review fixes 2026-11-19 (Mac: 1.48 s
          → 0.57 s CPU per photo):**
          effort 0 for `source.webp`, effort 2 for the display sizes
          (libvips' WebP writer called directly: `Image.write/3`'s
          1–10 effort scale can't reach 0), the upload decoded once
          into memory instead of four times, and the four files stored
          at the same time. `source.webp` stays first and in the
          foreground (no background job until Oban, see 7a).
          **Fly after 3a (2026-11-19, 13:14 Vancouver time):** photos
          2–8, the same ones as in the run before, at full speed:
          **~1.5 s CPU each, was ~3.8 s (2.5× less, as on the Mac)**;
          storing 0.1–0.24 s, was 0.26–0.76 s. 20 photos in 5.2
          minutes instead of 16.5; slowed-down photos took 37–53 s
          instead of 45–110; peak memory 453 MB. The first photo is
          slower in every run (3.1 s; 4.6 s before): getting started.
          Lesson: photos 9–14 showed 3.5–4.7 s of CPU *and* the same
          processing time, so mild slowing down raises both together
          and the tool's "full speed" rule (processing < 1.25 × CPU)
          didn't catch it; it only caught heavy slowing down. Fair
          comparisons: the same photos at the start of a run, on a
          Machine that has been idle (or on the Mac, never slowed). So
          the tool's summary now reports photos 2–8 instead, and warns
          if they were clearly slowed down.
          At 1.5 s: one performance core ~2,400 photos an hour; our
          shared CPU ~150 an hour sustained, a full 500 s burst ~330
          photos; Victoria's ~400 in an hour is ~17% of one
          performance core.
          Load to plan for (developer, 2026-11-17): 10–20 artists
          onboarding at the same time in Victoria; for Vancouver
          (bigger, its own instance), several hundred at once.
          Measure on Fly with the timing logs after each:
          a. Server tuning, no JavaScript: a lower WebP `effort` (on
             the Mac, 2500px: effort 4 = 335 ms / 1113 KB, effort 2 =
             171 ms / 1119 KB, effort 0 = 99 ms / 1143 KB), and make
             `source.webp` *after* the display sizes, in the
             background, so the artist only waits for the sizes. Also
             consider making the sizes in one pass. Guess: ~5 s → 1–1.5
             s per photo on Fly.
          b. Process each photo as soon as it's picked, in the
             background, so most of the work is done before Save.
          c. Shrink photos in the browser before upload (smaller
             uploads on slow connections, less server work): quick
             trial on an iPhone and the Mac, then the hook. The trial
             page (`priv/static/trials/`, plus `trials` in
             `ArtsyNeighborWeb.static_paths/0`) is temporary: remove
             both when 3c is done. `Release.check_before_launch/0`
             refuses while it's still served.
             *Built 2026-11-20:* the hook `assets/js/photo_shrink.js`,
             checked in Chromium, Firefox and WebKit (details and what
             was added beyond the plan in the plan doc, "What was
             built"). Next: the developer's iPhone on the preview, then
             remove the trial page.
          Very large photos (warn, then a low-priority lane): #43,
          designed together with b and c.
          **Plan for c then b (2026-11-19, order: 3c, 3b, then the
          audit):** `docs/plans/2026-11-19-browser-shrinking-and-early-processing.md`.
          Decided: the browser only shrinks; it never makes the
          display sizes. The server must encode every file it serves
          itself: a crafted image can attack visitors' browsers (e.g.
          the 2023 WebP flaw CVE-2023-4863, used in real attacks), and
          encoding is the expensive part anyway, so making the sizes in
          the browser would save only the cheap shrinking.
       The audit of 2026-11-15
       (kept locally in `docs/private/`, which git ignores)
       is to be addressed after these.
3. **Buyer + vendor features** — artist-page collections and the empty
   "Uncategorized" fix (#13), purchase history (#11), vendor tools and
   product status (#16; leaning towards leaving visible-but-`:unavailable`
   products out of the first release), sales page with reviews/stats (#12).
4. **Admin support tools** — enough to quickly find, view, edit, restore,
   or soft-delete any user/artist/product/order/review (part of #1).
   Includes the restore-button no-op and the missing `/admin/reviews`.
   Full flag moderation is NOT in this step (see 7).
   *Added 2026-11-09 (image storage step 2a):* admins can't publish a
   product. The admin "new product" form publishes it straight away if
   it has a photo, but a product created without one stays `:draft`,
   and neither the admin edit form nor the admin list can publish it
   (or a restored, `:unavailable` one) afterwards. Needs a Publish
   action (`Products.publish_product/1`) in the admin product pages.
5. **Email + focused security check** — real outgoing mail (#2, #10);
   basic authorization checks (can a vendor touch another vendor's data,
   can a buyer see another buyer's orders, upload safety) — part of #21.
   Includes the `return_to` links (noted 2026-10-26): "Back to …" links
   and the report form (`FlagLive.New`) use `return_to` from the address
   as it comes, so a crafted link could send a visitor to another site.
   Accept only paths on our own site (starting with one `/`, not `//`),
   in one shared check.
   *Added 2026-11-14:* account security for every outside service
   (#36) — not urgent for the private preview, but done meticulously
   before testers and again before launch.
   *Added 2026-11-19:* **keep libvips and the libraries behind it up to
   date** (libjpeg, libwebp, libheif, libde265, libpng, libtiff). The
   server rebuilds every upload from its pixels, so nothing hidden in a
   file survives, but a specially crafted image could still attack the
   image decoder itself while our server reads it (real cases: the 2023
   WebP flaw CVE-2023-4863, used in attacks). These libraries come from
   Debian through the Dockerfile, so they only get security fixes when
   the Docker image is rebuilt and deployed. Decide: a regular rebuild
   (e.g. monthly, and soon after a libvips/libwebp/libheif advisory),
   perhaps automatic (GitHub Actions, with the precommit check), and
   how we hear about advisories (Debian security announcements).
   `Release.image_support()` prints the libvips version (8.16.1 on Fly,
   2026-11-19). The upload size limits (25 MB, 52 MP) also help: they
   keep a crafted file from using up memory.
   *Added 2026-11-19:* **a rate limit on photo uploads per account**
   (developer's decision). Today one artist account could upload photo
   after photo, all of them legitimate, and keep both limiter slots
   busy so other artists wait or get "site is busy". The per-photo
   limits (25 MB, 52 MP, refused from the header alone) and the
   limiter (2 at a time) protect memory, but not fairness. Needed: at
   most N photos per account per hour (N from real use: an artist
   setting up a store adds maybe 20–50 photos in an evening), counted
   on the server (the browser can be bypassed), with a plain message
   when it's reached ("You've added a lot of photos in a short time.
   Please wait a few minutes and try again."). Only logged-in artists
   and admins can upload, so this is per account, not per IP. Check
   whether other actions need the same (sending messages, flag
   reports, log-in attempts).
6. **Developer's own rehearsal** on the deployed site, as vendor, buyer,
   and admin; fix what turns up. Then **invite testers**.
7. **Before public launch** — full flag moderation pass (rest of #1),
   payments (#3, #4), anonymization (#9), thorough security audit incl. an
   experienced human reviewer (#21).

Test audit (#19) runs alongside, not as one block: in each pass, walk
through that area's tests (what they check, what's missing). A session
on how the test suite is organized is a good first step.

## Known bugs

- **Sending a message to artist seems to crash LiveView at messages route for the recipient on the deployed site.

- **Registration crashes on the preview (prod)** (found 2026-11-04).
  The user is saved, then sending the confirmation email crashes the
  LiveView: prod still uses `Swoosh.Adapters.Local`, whose storage
  process doesn't run in a release (`no process ...
  Swoosh.Adapters.Local.Storage.Memory`). The form comes back blank,
  so it looks as if nothing happened, and a second try says the email
  is already taken. The account stays unconfirmed. Fixed properly by
  real email (step 5); before any tester registers, at least make a
  mail failure not crash the page. Workaround used: confirm the user
  and set a password from the remote console (`docs/deploy.md`
  section 5).
- **Password login gives no visible clue when the username is typed
  instead of the email** (found 2026-11-04 on the preview). Several
  failed tries, no message seen. To check: whether the browser's own
  `type="email"` check blocks the submit with a small, easy-to-miss
  popup, or whether the "Invalid email or password" flash
  (`UserSessionController`) doesn't show up. Fix: a clear message
  right under the field, e.g. "Please enter your email address, not
  your username." Matters for older users.

-* IN the conversation window between a vendor and an artist: add a note saying that to make a purchase click button in the correcponding products' webpage. or you can do it from a panel here and add a button to open a panel to choose a product from this specific artist, perhaps with search field. Should be similar to the same panel that vendors have for this purpose.

## Known limitations / deliberately deferred

Things that are knowingly incomplete by design (not bugs), and that anyone
working on the code should keep in mind.

- **Tailwind binary needs re-signing on macOS 27** (found 2026-11-06).
  The binary that `mix tailwind.install` downloads into `_build/` has
  an invalid ad-hoc code signature; macOS 27 kills it on start (exit
  137), so the stylesheet silently stops rebuilding while pages still
  load with the old `app.css`. Fix after every fresh download (e.g. a
  Tailwind version bump, or a deleted `_build/`):
  `codesign --force -s - _build/tailwind-macos-arm64*`. Check with
  `codesign -v _build/tailwind-macos-arm64`. Not an issue on Fly
  (Linux).
- **Upload storage is dev-only.** Photos go through `ArtsyNeighbor.Storage`,
  whose only backend so far is `Storage.Local`: public sizes in
  `priv/static/uploads/`, which is wiped on deploy, and the private
  `source.webp` in `priv/private_uploads/`. `Storage.S3` (Tigris) is
  step 2c of the order of work.
- **Delivery as a fulfillment method is schema-only.** `delivery_options` can
  contain `"delivery"` but nothing in the UI lets a buyer choose it, and
  `complete_pickup/2` has no delivery clause. Not planned for initial launch.
- **No real payment processing yet.** Charge/refund functions are `Logger`
  stubs; a `payment_method` field (cash/Interac) is planned but not yet on the
  `Order` schema.
- **Flagging: reporting works; admin moderation doesn't yet.**
  Buyers/vendors can report a rogue vendor, product, or buyer via
  `/flag/:subject_type/:subject_id` (`FlagLive.New`) — see
  `Reviews.resolve_subject/2` and `Reviews.create_flag/1`. Since the
  artist page's step 5a (2026-10-23), reviews of artists are shown
  publicly on the artist's Shop tab, each with "Report this review"
  (`vendor_review_of`). Product and buyer reviews still aren't shown
  publicly, so `product_review_of` / `buyer_review_of` have no links yet.
  Reports are only stored: there is no `/admin/flags` moderation view
  (review/resolve/dismiss reports) and no notice to a reporter when their
  flag's status changes, which depends on that view existing. Fine
  while only we use the site; needed before testers.

## Deferred follow-ups (small, scoped)

- **Two pieces of noise in the `mix test` output** (noticed
  2026-11-04; both already there before the ecto/phoenix_html update,
  all tests still pass):
  - A red `GenServer terminating ... FunctionClauseError` from
    `UserLive.Settings`. In tests, Swoosh's test adapter sends each
    email as an `{:email, ...}` message to the sending process, here
    the settings LiveView, which has no `handle_info/2` clause for it.
    Test-only (prod uses a real mailer). Fix: a catch-all
    `handle_info/2` clause that ignores unexpected messages.
  - An "unused default value" warning for `insert_conversation/3` in
    `test/artsy_neighbor_web/live/conversation_live/index_test.exs`:
    drop the `\\ %{}`.

- **"Show password" option on every password field** (added 2026-11-02,
  after the developer typed a long password on the live site unsure of
  what she had typed). A plainly labelled checkbox or button with words
  ("Show password"), not just an eye icon, on log-in, registration,
  settings (new password) and reset. Fits the older audience (see
  "Order of work" step 1 principles). Small JS hook or a few lines in
  `app.js` toggling the input's `type` between `password` and `text`;
  keep it off by default.

- **Check form recovery on every form** (added 2026-10-30). When the
  LiveView connection drops (Wi-Fi blink, phone asleep, **every
  deploy**, Fly auto-stop), the browser reconnects and the server
  starts the page over from `mount`, so anything kept only in assigns
  is lost. LiveView's "form recovery" puts typed text back: on
  reconnect it re-sends each form's current fields as a `phx-change`
  event. It only works for a form that (1) has a `phx-change` handler,
  (2) has an `id` (LiveView 1.2 warns in tests when missing; ids were
  added to four forms 2026-10-29), and (3) keeps the state in the
  form's own fields. A form that doesn't qualify silently loses what
  the person typed, which matters most for long texts typed slowly on
  phones. To do:
  - **Stars in the buyer and vendor review forms** (`ReviewLive.OfBuyerStep`,
    `OfVendorStep`): the rating lives in `@stars`, set by the star
    buttons outside the form, so after a reconnect the comment comes
    back but the stars are blank. Fix as in `OfProductsStep`: a hidden
    `<input name="stars">` inside the form, and read it in the
    `form_changed` handler.
  - **Pickup scheduling form** (`ConversationLive.Show`, `phx-submit=
    "submit_schedule"`): no `phx-change`, so no recovery. Add one if
    people type more than a date there.
  - **New collection modal** (`VendorLive.ProductForm`,
    `phx-submit="save_new_collection"`): no `phx-change`, no `id`.
    Short field, low priority, but the modal also closes on reconnect.
  - **Uploads can't be recovered** (browsers don't allow refilling a
    file field): a photo chosen but not yet saved is lost on
    reconnect. Consider a plain message when that happens, at least
    on the vendor product form.
  - **Then go through all the rest** (about 30 `<form>`/`<.form>` tags
    in `lib/`; list them with a search for `<form` and `<.form`) and
    check each against points 1–3. Forms that only hold buttons
    (`method="dialog"` closers on the product page) don't need it.
  - Test it by hand: type into a form, restart `mix phx.server`, and
    see what comes back. Whether LiveView tests can check recovery
    automatically is a question for the test audit (#19).

- **No PubSub broadcast when a message is soft-deleted.** `ConversationLive.Show`'s
  `delete_message` handler (`show.ex`) updates the DB and the deleting
  user's own view via `stream_insert`, but doesn't broadcast to the other
  party's open tab — they won't see the "Message deleted" placeholder until
  they reload. Deliberately left out of the Conversation/ConversationEvent
  status-field commit (2026-09-24) — wanted as its own separate, small
  commit, possibly after the whole entity-removal-consistency pass wraps.
- **`find_or_create_conversation/2` and `get_or_create_system_conversation/1`
  don't account for an archived conversation.** Both do a bare `Repo.get_by`
  that could resolve to a `:archived` row; since `get_conversation/1` is now
  scoped to `:active`, a buyer who re-clicks "message artist" after an
  admin archives their old thread would hit a confusing dead end (the
  underlying `find_or_create` succeeds, but the resulting show page 404s).
  Not reachable today — nothing yet lets anyone actually call
  `soft_delete_conversation/1` outside a test. Needs a real product
  decision (revive the old thread? start fresh? something else?) once the
  admin conversations screen is built.
- **`create_message_event/4` doesn't check `conversation.status`**, found
  via `/code-review` of the Conversation/ConversationEvent status-field
  work (2026-09-24). `ConversationLive.Show`'s `post_msg` handler
  (`show.ex`) uses the `conversation` struct captured once at mount/patch
  time, not re-fetched per event, so a participant with the thread already
  open when it gets archived could keep posting into it until they reload
  — contradicting soft-delete's "hides/mutes it from both participants"
  intent. Not reachable today (no admin UI calls
  `soft_delete_conversation/1` yet); fix alongside the admin conversations
  screen, likely by re-checking status in `create_message_event/4` itself
  rather than trusting the socket's stale assign.
- **`get_or_create_system_conversation/1` looks up a user's system
  conversation unscoped by status** (unlike every other lookup in
  `conversations.ex`, which goes through `with_status/2`), also found via
  the same `/code-review`. The system-conversation partial unique index is
  keyed only on `conversation_type = 'system'`, with no status qualifier —
  so once a user's system conversation is archived, a fresh one can never
  be created, and `post_system_message/2` silently keeps writing into the
  archived row. Both read paths (`list_system_conversations_for_user/1`,
  `list_unread_system_conversation_ids_for_user/1`) are `:active`-scoped,
  so those messages vanish from the user's inbox with no error anywhere.
  Same "not reachable until the admin conversations screen exists" caveat
  as the bullet above — fix both together.
- **Restore button can silently no-op.** `AdminArtistLive.Index`/
  `AdminProductLive.Index`'s restore-button visibility (`status != :active`
  / `status != :available`) is broader than what `restore_artist/1`/
  `restore_product/1` actually handle — clicking restore on a merely-
  `:inactive` artist (not `:removed`) or merely-`:unavailable` product (not
  `:archived`) is a no-op that still shows a "restored" success flash.
  Found via Phase 2's partial `/code-review` (2 of 8 angles ran).
- **Two admin-status-dropdown cascade gaps**, same root cause as the fixed
  `:removed -> :active` bypass (Phase 1 commit 3) but different transitions:
  `:active -> :removed` skips the product-archive cascade;
  `:removed -> :inactive` skips `restore_artist/1`'s `:user_missing` guard.
  Low severity today.
- **`Product` has no `status_changed_at` column**, unlike Artist/Category/
  Review — never added, so there's no way to answer "when was this product
  archived?" Needs a migration + wiring `maybe_set_status_changed_at/1`
  into `Product.status_changeset/2`.
- **ILIKE wildcard characters aren't escaped** in `with_search_term/2` and
  siblings (product/category/artist search) — pre-existing, low severity.
- **`filter_artists_by_area/1`/`filter_artists_by_medium/1` are dead code**
  with the same missing-status-filter shape as a bug already fixed in
  `filter_artist_products/2` — latent trap if either ever gets wired up to
  a real caller.
- **`test/support/fixtures/conversations_fixtures.ex` is stale** —
  `conversation_fixture/2` calls a removed `create_conversation/2`. Not
  used by anything currently passing; fix if touched.
- **No admin-LiveView test coverage exists anywhere** (no `log_in_admin`/
  admin fixture helper) — noted since Phase 0, never addressed.
- **A work should always have a category** (decided 2026-10-23). The
  product form requires one, but the database doesn't:
  `products.category_id` is nullable, and hard-deleting a category sets
  it to null on that category's works. `AdminCategories.hard_delete_category/1`
  only refuses when the category has *available* works, so its
  unavailable/archived works lose their category, and restoring one later
  can make it available with none. Plan: a catch-all category (name to
  pick, e.g. "A class of its own") that such works move into instead of
  losing their category; then `category_id` can be made required in the
  database. Deleting a category that has no works stays allowed. Until
  then, `Products.shown_collections/2` skips works without a category so
  the Shop tab's chip counts match its list (found in step 4's code
  review).
  Revisit too (2026-10-26, home page step 3's code review): the
  all-works page (`Products.filter_products/1`) now lists works without
  a category (a left join), because the home page's New works showed
  them and "See all new works" left them out. Once every work is sure
  to have a category, decide whether to change it back to an inner join
  and drop the "no category" handling there (and in
  `list_similar_works/2`, `shown_collections/2`).

- **Logging in from the artist page doesn't come back to it** (found
  2026-10-23, artist-page step 6). "Log in to message" on the Contact
  and Commissions tabs goes to `/users/log-in`, and after logging in the
  visitor lands on the usual signed-in page, not back on the artist.
  The return path (`:user_return_to` in `UserAuth`) is only stored when
  a logged-out visitor is bounced from a page that requires login. Fix:
  pass the artist page along (e.g. a `return_to` param the login page
  stores in the session), checking it's a path on this site so it
  can't send people elsewhere. The same applies to "Create an account".

- **UI to request commissions** . It basically comes down to a fancy looking entry-point (button) which opens the chat between artist and buyer. But we do need to include a way for the artist to bill buyers through the system, thus collecting our share

## Features / next chunks of work

1. **Admin moderation pass** . **Must include a screen for reports
   (`/admin/flags`)**: since 2026-10-23 the artist page has "Report this
   review" links, so review reports are being collected with no way yet
   to see or act on them (reports of artists, works and buyers too).
   The admin UI right now is a rough draft. It is incomplete and inconvenient for any even a small volume of users. Need to add good comfortable UI to moderate vendors, users and buyers, reviews, products and to resolve flags. Not sure if UI for moderating converstions is needed. Also not sure what it may look like.

 `/admin/flags` (review/resolve/dismiss
   reports) and notifying a reporter when their flag's status changes
   (reviews of artists and their "Report this review" links are on the
   artist page since 2026-10-23; product reviews follow with the product
   page). **Design decision already made, not yet built:** `Flag` needs
   a new status (e.g. `:subject_removed`, not `:dismissed`/`:removed`) for
   when a flagged review is soft-deleted by its own author before any
   admin acts on the flag.
   This pass is also where the still-missing `/admin/conversations` screen
   (to actually call `Conversations.soft_delete_conversation/1`/
   `restore_conversation/1`) belongs, and, same shape of gap, a still-missing
   `/admin/reviews` screen — `Reviews.soft_delete_*_review/2`/
   `hard_delete_*_review/1` exist in the context but nothing in the admin UI
   calls them; confirmed no `/admin/reviews` route exists today.
2. **Email scaffolding** — buyer gets a completion link by email when the
   vendor schedules pick-up (Swoosh is already in the project).
3. **Payment options** — cash or Interac at the door; needs a
   `payment_method` field on orders.
4. **Payment scaffolding** — `Logger` stubs for `charge_buyer`,
   `charge_platform_fee`, `issue_refund` (Stripe drops in later).
5. **Styling pass** — deferred; do a dedicated design-mockup session
   before touching real code. I also refer to it as UI pass. UI right now it pretty roughm so far we have focused on having functionality in place. 

  But I do want to keep the site light weight

6. **Multi-item cart on `ArtistLive.Store`** — deferred.
7. **Delivery completion flow** — deferred, not planned for launch. Likely for subsequent releases.
7a. **Smart search (later, after launch; discussed 2026-11-17)** —
   search products by meaning using text and image embeddings, maybe
   a chat helper on top. Plan as discussed:
   - Embeddings from a **hosted embedding service** (an API call per
     product save and per search), not a model run on our own server:
     a local image model needs hundreds of MB of memory and a lot of
     CPU, which is just what our small machine lacks. Products and
     photos are public anyway; search text goes in the privacy policy.
   - Vectors in Postgres with **pgvector**. A few thousand products
     need no special index. Fly's own unmanaged Postgres image
     (`flyio/postgres-flex`) does **not** include pgvector (checked
     2026-11-17); Fly Managed Postgres (from $38/month) and Neon do.
     So it counts in the Postgres/Neon decision.
   - A **job queue (Oban, jobs kept in Postgres)** for computing
     embeddings after a save, retrying when the service is down, and
     re-embedding everything after a model change. Add it with this
     feature, not before (see #34).
   - The private `source.webp` of every photo stays: it lets image
     embeddings be computed or recomputed later.
   - A chat helper would call an LLM API with search as its tool:
     nothing heavy on our server.
8. **Vendor/admin polish**: vendor dashboard preview-before-going-live;
   admin can already set all three artist statuses, vendor can only
   toggle active/inactive (by design).
9. **User anonymization ("forget me")** — for privacy requests
   (PIPEDA / Quebec Law 25), anonymize rather than hard-delete: keep the
   `users` row so orders/reviews/flags stay intact for the other party,
   scrub `email`/`username`/`hashed_password`, kill sessions, set status
   `:removed`. Depends on Phase 7's User `status` and on the per-FK
   product decisions listed in Phase 7 of
   `docs/plans/2026-09-17-entity-removal-consistency.md`. True hard
   delete of users stays dev/testing-only (or for accounts with no
   history at all).
   **Before testers (added 2026-11-16, from the review of the sample
   data script): make User `status` actually work.** Today nothing
   reads it: a `:suspended` or `:removed` user can still log in, and
   there is no way to suspend or remove an account. Needed: log-in
   (password and email link) and every page load refuse non-`:active`
   users and end their sessions; an admin "suspend user" button
   (moderation, e.g. a spammer); then this anonymization. Fits the
   "admin support tools" step. Until then,
   `SampleData.remove_all/0` locks sample accounts the only way that
   works now: a random password nobody knows plus deleting their
   sessions (it also sets `:removed`, ready for when status counts).
10. **Test real outgoing mail** — dev uses `Swoosh.Adapters.Local`
    (`/dev/mailbox`), so no mail has ever actually been delivered. Once a
    real adapter/staging exists, verify registration, login, and
    email-change mails actually arrive (Gmail `+` aliases, e.g.
    `name+buyer1@gmail.com`, give unlimited test addresses).
    Email change itself already exists (`/users/settings`, generated by
    `phx.gen.auth`) — just needs a smoke test and better discoverability
    in the styling pass.

  11. **All users need to be able to see their Purchasing History**. It is not built yet.
  12. **Sales history** for sellers (now named Orders) needs a brush up. It would be good to have a way for sellers to see their reviews and summary statistics at a glance.
  13. Artists home pages (/artists/:id): the section showing collections is not wired up. Links do not link to anything. Also collection "Uncategorized" shows even when it is not empty. It also appears in the drop down box in /artists/:id/store even when it is empty. The "Uncategoriezed" collection should not show when it is empty.
      - *Done 2026-10-22 (artist-page step 3):* collection cards open the Shop tab filtered to that collection; the cards and the Shop tab's collection filter both leave out "Uncategorized" and collections with no available works (`Products.list_public_collections_for_artist/1`, and `list_collections_for_owner_preview/1` for the owner's preview).

  14. The name of the website in the end will be LocalPalette, not ArtsyNeighbor. We need to adjust UI for that. Code can remain as is (we do not need to rename the project)

  16. Do a pass on Vendor dashboard and tools. Editing products from Vendor dashboard is very rough. We want to be allow vendors to set status of products to :archived. They should be able to see them in their list of products clearly labelled as Archived so they can restore them with minimal changes. I am also contenplating allowing them to have :unavailable products - those they are working to make more of, sort of sold out products. These would show on their stores but could not be purchased until status changes. Not sure if this later should be included in the first release.
      - *Added 2026-10-22:* vendors need toggles to make each work
        available / unavailable / archived. Today there is no way back:
        deactivating a profile cascades every `:available` work to
        `:unavailable` (`Artists.deactivate_artist/1`), and reactivating
        doesn't restore them. `Products.restore_product/1` exists but
        has no vendor UI, and it requires the artist to be `:active`, so
        it can't make works available for a profile that's still in
        preview.
      - *Test then:* the owner's preview (`/artists/:id?preview=1` on
        an inactive profile) should show available works on the Works
        and Shop tabs and their collections (built in artist-page
        step 3, so far only covered by automated tests).
      - *Added 2026-10-23:* a vendor can't see their own work's
        product page while it's unavailable: `/products/:id` only shows
        available works and otherwise sends them to `/products` with
        "Product not found". With the toggles, the product page needs an
        owner preview like the artist page's `?preview=1`.
      - *Added 2026-11-09:* image storage step 2a adds a temporary
        product `:draft` status (a product without photos can't be
        available) with Save draft / Preview / Publish buttons on the
        vendor product form, and the product page's owner preview
        (`/products/:id?preview=1`). This pass should replace that with
        the real thing: artists switching each work between draft,
        available, unavailable and archived from the dashboard. See
        `docs/plans/2026-10-28-image-storage-and-resizing.md`.

  17. I need some solid advice and to make decisions about how to store images. Right now everything is local on my laptop, I have no idea how to set it up so it would work on server.
      - *Decided 2026-10-28:* uploads go to object storage (Tigris on
        Fly; S3-compatible, so R2 or AWS work with the same code).
        Images that are part of the site stay in git under
        `images/site/` and `images/seed/`; working files live outside
        the repo. Embeddings (later) go in Postgres via pgvector and
        don't change this. Steps: "Order of work" step 2, a–c.

  18. I am contemplating a "testing" hosting on on Fly.io or similar service. I want it to be unaailable to public for now, only to a few selected testers. And also as a way to even see what is involved in setting it up on a server. 

  19. Audit of tests: for now they are all written by Claude, most decisions are made by Claude and I only skim them. This is one of my weaker points as I have never done true deployment. But I do want good informative test covereage. So I suppose an audit of existing tests and probably extending them.
      - *Added 2026-10-28:* also decide whether to add a small browser
        test suite (Playwright, e.g. via `phoenix_test_playwright`) for
        what only a real browser exercises: our JavaScript (large-view
        modal, scroll listeners) and flows across several pages. Not
        added during the image-storage step on purpose: the LiveView
        tests cover uploads, and a browser suite makes every test run
        slower and needs Node + a browser.

  21. A very serious and thorough security audit. I am thinking of running Claude Fable on it and later (or earlier) also askign an experienced human developper for suggestions. I have no experience in this area.

  22. **A real phone app**, wanted in the near future (added 2026-09-28).
      The site is built mobile-friendly first; how to make the app (an
      installable web app, LiveView Native, or a separate app talking
      to the server) is still to be decided.

  23. **Featured works on the artist profile** (added 2026-10-02). The
      artist page shows a "Featured works" row right under the artist's
      details, so their best work is visible without scrolling (see the
      artist-page mockup). Artists need a way to choose which works are
      featured (and probably their order) from their vendor tools —
      belongs with the vendor tools pass (#16). Needs a product decision
      on how many (four fill one row) and what shows if none are chosen.
      - *2026-10-22:* the Works tab now shows the 4 newest available
        works as a stand-in (artist-page step 3). Choosing waits for the
        vendor tools redesign, not the artist-page steps. Suggested
        shape: an optional `featured_position` (1–4) on products, a
        "Feature on my page" switch in the vendor's product list, and
        the newest works filling any places not chosen.
      - *2026-10-28:* the home page's artist cards (Popular artists) use
        the same works: the banner is the first featured work. Both get
        them from `Products.list_newest_artist_products/2`, so changing
        that function (or replacing it) changes both.

  22. Small issue in messages/id route: basically showing a conversation. Both Chorime and Firefox remember and keep suggesting what you had previously typed in it. Because this is a free form text this is odd. It's not an address/name or other reocurring field. Not sure if this is an issue witha browser or my code. But not too big of a deal.

  24. **Check and process uploaded images automatically** (added
      2026-10-07). **Done 2026-11-09** for product and artist photos
      (step 2b of the order of work; collection covers don't exist
      yet). Image sizes are mystifying to most people, so artists
      should never have to think about pixels or file sizes. On upload
      (product photos, collection covers, artist photos): accept any
      ordinary photo; refuse only ones that are genuinely too small, in
      plain words ("This photo is too small to look good. Please use a
      larger one." — e.g. under ~800px on the long side); then
      automatically resize and compress to web sizes (a thumbnail size
      for tiles plus a larger one for the product page). Probably also
      check the file really is an image (part of the security check,
      #21). Ties in with image storage (#17) and the dev-only upload
      storage under "Known limitations". Tiles on the artist page crop
      to a landscape 4:3 shape (decided 2026-10-07), so the product page
      must always show the whole, uncropped work; a later option is to
      let artists choose which part a tile shows.
      - *Added 2026-10-23:* keep a large version of each product photo
        too (e.g. up to ~2000–2500px on the long side), not only a
        page-sized one: the product page's large view (and any later
        zoom) can only show pixels that exist.

    25. Add ability for buyers to Follow artists. This means a button to opt in and also a clear interface for vendors to send updates tp subscribers.

  26. **New Artist fields shown in the artist-page mockup** (added
      2026-10-19). Left out of the restyled artist page until they
      exist; each needs a field, a place in the vendor profile form, and
      its spot on the page:
      - **Motto**: one optional short line under the name ("Oils with a
        splash"), separate from the temporary `announcement`.
      - **Returns policy**: the artist's own text, shown in a "Returns"
        section at the end of the Shop tab.
      - **Takes commissions (yes/no)**: chooses the Commissions tab's
        text. Until then the tab shows the same fixed "takes
        commissions" text for every artist (decided 2026-10-19), so it
        says so even for artists who don't; see the commissions item
        above and the plan doc's "Artist page" section.
      - **Studio visits**: whether the artist welcomes studio visits
        (and how: by appointment, open-studio days), shown in a
        "Studio" section on the Contact tab as in the mockup ("Fernwood,
        Victoria. Studio visits by appointment — ask in a message").
        Left out in step 6 (2026-10-23) so the page doesn't promise
        visits for every artist; the neighbourhood part waits on #28.

  27. **Artists index: cards per row by screen size** (added
      2026-10-19). `ArtistLive.Index` cards are fine 4 to a row on a
      laptop but far too big on a large monitor; more per row on wider
      screens. For when Phase E reaches that page.

  28. **Postal code → neighbourhood name** (added 2026-10-21, wanted
      soon). Artists enter a full postal code (`area_code`), which can
      narrow down to one block, so it shouldn't be public. A small
      module mapping its first 3 characters (the district, e.g. "V8V")
      to a Victoria neighbourhood name ("Fernwood · Victoria" in the
      mockup). Until then the artist page header shows only the first
      3 characters ("V8V · Victoria"). Also still showing the full code
      publicly: the artists index cards (`ArtistLive.Index`) and its
      "Neighborhood" sort; and the vendor profile form's label says
      "visible to customers", with a full code as its example.

  29. **Better "You may also like" on the product page** (added
      2026-10-26, no date yet). For now it shows the 4 newest works by
      other artists in the same category (`Products.list_similar_works/2`),
      which is good enough to start with. Eventually it should suggest
      works by some measure of similarity (medium, subject, colours,
      price range, or the photos themselves) or by a recommender based
      on what visitors look at and buy. Swapping it in only means
      changing that one function.

  30. **Choosing the home page's featured work** (added 2026-10-26).
      The hero shows a detail of one work, set by hand: the picture and
      its alt text in `config/config.exs` (`:home_hero`), the work's id
      per environment (86 in `dev.exs`; on the deployed site the
      `HOME_HERO_PRODUCT_ID` environment variable, read in
      `runtime.exs`; without it the picture has no credit or link). Later: an admin
      page to pick the work and upload its detail picture (one the
      artist supplied or approved), changed every week or two
      ("featured artist"); perhaps a paid placement one day, then
      labelled as such.
      Found in code review (2026-10-26):
      - *Fixed 2026-10-26:* the work's id was the same in every
        environment, so on another database the picture could carry
        another artist's name. Now set per environment (above). At the
        private deploy (step 2 of the order of work): add the work and
        its photo there, then set `HOME_HERO_PRODUCT_ID` to its id.
        After a reseed of dev, check that 86 is still Protectress.
      - **Still open, for the admin page: a non-`:active` artist is still credited.** `get_hero_work/1`
        doesn't check the artist's status, and the unlinked credit
        still shows when the work isn't for sale. So a removed or
        inactive artist's name and postal district would stay on the
        home page. The credit should only show for an `:active` artist.

  31. **Better choice of works for the home page's "New works"**
      (added 2026-10-26, no date yet). For now it shows the 8 newest
      works on the site (`Products.list_newest_works/1`). One artist
      adding a batch of works fills most of it (in dev data, 6 of 8 were
      one artist's bowls). On the live site the newest works aren't
      necessarily the best ones to show: better a curated selection
      (admin-chosen, like #30) or the best-reviewed / most popular
      works. Nothing backs that yet (no curation tools, too few reviews
      or sales). A small stopgap if needed sooner: at most 2 works per
      artist. Swapping it in means changing that one function (and the
      section's name and "See all" link, if it stops being "new").

  32. **Let artists rotate their photos** (added 2026-11-06), as part
      of adding photos in the product and artist-profile forms. Uploads
      are already turned upright automatically using the photo's own
      orientation note (EXIF), so they look the way they did on the
      artist's phone. But a photo that was *taken* sideways (phone
      tilted while shooting a painting) looks sideways on the phone
      too, and only the artist can tell. A simple "rotate left / right"
      button next to each photo, re-making the stored sizes from the
      private `source.webp` (see the step b plan,
      `docs/plans/2026-10-28-image-storage-and-resizing.md`).

  33. **Help artists whose photo is "too large"** (added 2026-11-09).
      Uploads over ~52 MP are refused (memory on the server; see step
      2c). Normal phone photos (12–24 MP, or 48–50 MP modes) pass, but
      a Samsung 200 MP mode photo, a big scan or a stitched panorama
      won't, and many of our artists are older and won't know how to
      make a photo smaller. Options, possibly together:
      - next to the "too large" message, a short plain-words guide
        (link or expandable) per device: iPhone (share by Mail and
        pick "Medium"/"Large", or set the camera back to 24/12 MP),
        Samsung (switch the camera out of 50/200 MP mode), Mac
        (Preview → Tools → Adjust Size), Windows (Photos → Resize);
      - a general "Photo tips" help page (also good for lighting,
        backgrounds, cropping);
      - *added 2026-11-19:* maybe a link to a free, trustworthy tool
        for making a photo smaller (one that works in the browser
        without uploading the photo anywhere, or the computer's own
        photo app), for the rare over-limit photo the browser can't
        shrink itself;
      - accept big JPEGs anyway by reading them at ½ / ¼ / ⅛ size
        (libvips "shrink-on-load", cheap in memory), so only big
        HEIC/PNG/TIFF files would still be refused. More code; only
        if artists actually hit the limit.
      - *Added 2026-11-19:* browser shrinking (photo speed 3c) will
        make most over-limit photos fit before upload (plan
        `docs/plans/2026-11-19-browser-shrinking-and-early-processing.md`,
        3c point 9).
      - *Added 2026-11-19:* **once a year, check what new phones save**
        and whether the server's limits (25 MB, 52 MP) still cover
        them (as of mid-2026: normally 12–24 MP; optional modes 48–50
        MP, Samsung 200 MP; panoramas 60–100 MP). Raising 52 MP costs
        server memory (a 48 MP photo peaked at ~460 MB), so measure
        again with `Release.time_photos/1` first.

  34. **Photo processing is a bottleneck — rethink it systematically
      before the site gets busy** (added 2026-11-09, code review of
      step 2b). Each server machine processes at most N photos at once
      (`ArtsyNeighbor.Images.Limiter`, N = 2, set in `config.exs`); a
      photo waits up to 30 s for its turn, then gets "The site is busy
      — please try again in a moment". Photos of one save are
      processed one after another, each waiting on its own, so 5
      photos on a busy server can take minutes, or all end up "busy".
      The "Saving your photos…" box now says it usually takes a few
      seconds per photo (it used to promise "up to a minute"). Fine
      for testing and the first months. Later, decide together:
      - more memory / more machines, and the right N (step 2c);
      - a real job queue (e.g. Oban, with jobs kept in Postgres) so
        photos are processed after the page has moved on, survive
        restarts, and the artist is told when they're done;
      - processing as soon as a photo is picked (errors show while
        the artist is still typing; needs a temporary area for photos
        of a product that isn't saved yet);
      - a progress line per photo ("2 of 5 saved");
      - **shrinking photos in the browser before upload** (suggested
        2026-11-16 by the developer's husband, a senior developer;
        now step 2c item 3c). Measured later that day: most of the
        server's *time* goes into encoding the WebP files, not decoding
        (see step 2c item 3), so this helps mainly through smaller
        uploads and a smaller `source.webp`; decoding a full-size
        original still costs *memory*. A
        small JavaScript hook would redraw the photo at about
        2500–3000px (dropping its metadata, so GPS never leaves the
        phone) and upload that instead: faster uploads, less
        server work. The server keeps its whole pipeline unchanged,
        because a browser can't be trusted; if the browser can't
        shrink a photo (HEIC on Windows, very large photos on older
        iPhones, no JavaScript), the original goes up as today. It
        lowers the usual load, not the worst case: someone bypassing
        the hook can still send a large original, so the limiter and
        size limits stay. Open: how large `source.webp` can still be
        (it can't exceed what the browser sends). May make the queue
        and pick-time processing above unnecessary.
      Related: a photo can still leave stored files with no row if the
      server stops *while* that one photo is being written (a split
      second; the row is made right after). See #42.

  35. Artist cards on the home page. The artists to show are selected automatically and the banners are one of their works. However, most works do not display well in this wide landscape format and are cropped off. This needs fixing, likely by offering artists to upload a banner. This likely needs a separate UI page on Artists dashboard.

  36. **Protect the service accounts; limit what a break-in can cost**
      (added 2026-11-14). Fly has no spending cap and no billing alerts
      (checked 2026-11-14: "there's no soft ceiling"; prepaid credits
      don't stop service either, the rest goes on the card). So the
      real protection is the accounts themselves. Low priority for the
      private preview; do it meticulously before testers (step 5) and
      review before launch:
      - **GitHub** (Fly signs in through it, so it's the real door):
        two-factor with a passkey or authenticator app, not SMS;
        unique password in Passwords; check recovery codes are saved.
      - **Fly**: its own two-factor if offered for GitHub logins;
        review `fly tokens list`; CI (GitHub Actions) gets a deploy
        token for one app only, never an account-wide token.
      - **Card**: a separate (virtual) card with a low limit for online
        services, so its limit is the only hard ceiling. Ask the bank.
      - **Bill check**: glance at "current month to date bill" in the
        Fly dashboard weekly while things run (~US$9–11/month expected
        since the 1 GB app Machine).
      - Same review for any later service (domain registrar, email
        provider, Stripe): two-factor, who has access, project email
        address vs personal (see step 2 c).

  37. **Work cards crop photos** (added 2026-11-15, seen on the Fly
      preview). A portrait iPhone photo shows whole on the product page,
      but is cut off on the product card in the artist's shop and in
      the home page's "New works". Cause: the card picture box is a
      fixed landscape 4:3 (`.artwork-card-pic` in `assets/css/app.css`,
      `aspect-ratio: 4 / 3` + `object-fit: cover`), so a 3:4 portrait
      photo loses almost half its height. For art this matters: the
      buyer may never see the whole work on a card. Developer's leaning:
      scale the whole image to fit instead of cropping. Options to
      weigh (with mockups/screenshots):
      - `object-fit: contain` in the same box, with a calm background
        colour around the photo (simplest; cards stay in neat rows,
        but portrait works look small);
      - a box that follows each photo's own shape (cards of different
        heights, a "masonry"-style grid);
      - a square box + `contain` as a middle way;
      - later, let the artist choose the crop for cards.
      Same family as #35 (artist banners crop works), and the same
      `object-cover` choice appears in smaller places (artist cards'
      three-work strip, order and conversation thumbnails), which are
      less critical but worth a look in the same pass.

  38. **Vendor dashboard's product table doesn't fit on a phone**
      (added 2026-11-15, seen on the Fly preview). Held upright, the
      table is cut off on the right, so the View / Edit / Archive links
      (the last column) can't be seen; they only show with the phone
      turned sideways. The table (`vendor_live/dashboard.ex`, ~line
      227) is a 5-column daisyUI `table` inside `overflow-x-auto`, so it
      scrolls sideways, but nothing hints at that, and older users
      won't think to swipe the table. Fix ideas: on narrow screens show
      each product as a small card (photo, title, price, then the three
      actions as buttons below), or at least put the actions first or
      under the title. Check the other tables artists use on a phone at
      the same time (sales/orders list), and admin tables less urgently.

  39. **Deleting a photo leaves its files in storage** — **fixed
      2026-11-16** (`d00cb11`): deleting a photo row, or hard-deleting
      a product or artist, deletes the files too (soft deletes keep
      them). Checked on Fly (`docs/tigris.md` §3.5 check 6). Leftovers
      in rare cases: #42; browser caches: `docs/tigris.md` §2.

  40. **The admin category form needs serious re-working** (added
      2026-11-15; not urgent). It was one of the first pages written
      and predates the current conventions. Most visibly, its picture
      ("Main img") is a text box for a typed path, not an upload: the
      only photo field that skips `Images.process_upload` (via
      `PhotoUploads`), and the form shows the typed path straight in
      `src=` (`admin_category_live/form.ex` ~line 27–30; the
      `image_display_test` guard only looks for `.path`, so it doesn't
      catch it). Rework it like the other four photo forms, and review
      the rest of the form (slug by hand, layout, wording) at the same
      time. Until then, leave "Main img" empty: categories then show
      the placeholder.

  41. **Serve photos from our own domain before inviting testers**
      (added 2026-11-16). On the Fly preview, the developer's
      Malwarebytes (web protection) blocked both buckets'
      `*.t3.tigrisfiles.io` addresses as unsafe, and she had to add
      them to its Allow list. Nothing is wrong with our setup (valid
      Let's Encrypt certificate, plain HTTPS): security tools judge
      shared file-hosting domains by reputation, and attackers also
      host files on them. Similar blocks have been reported for other
      Tigris domains. For visitors with such a tool, photos would
      quietly not load. Fix: once we have our domain, point e.g.
      `photos.<our domain>` at the public bucket (a CNAME record plus
      `fly storage update ... --custom-domain`; check Tigris' current
      docs on whether the bucket name must match) and set the
      `PHOTOS_BASE_URL` secret, which `config/runtime.exs` already
      reads. The private bucket needs nothing: browsers never load
      from it. Fits with buying the domain (step 2 above / deploy
      runbook).

  42. **Periodic clean-up of photo files no row points to** (added
      2026-11-16, from the code review of #39; before real launch, not
      urgent). Deleting a photo row deletes its files (#39), but a few
      cases can still leave files behind: the server stops between the
      commit and the file delete, storage is unreachable then (logged
      as "Deleting photo files ... failed/crashed"), the server stops
      while a new photo is being written, or a future delete path
      forgets `Images.delete_files/1`. A scheduled job would list the
      image folders in storage, compare them with the `path` values in
      `product_images` and `artist_images`, and delete folders no row
      points to. Careful points: only folders older than a day (a photo
      being processed right now has files but no row yet); log what it
      deletes; try it in "report only" mode first. Cost of waiting:
      only storage space (negligible), plus the public address of an
      orphaned photo keeps working for anyone who has it.
      **The big case (added 2026-11-16):** the developer plans to start
      the preview's database over before inviting testers. Then *every*
      photo in the buckets belongs to the old database, so empty both
      buckets at the same time (or destroy and re-create them, as in
      the full teardown): `docs/deploy.md` §8, "Starting the database
      over". Removing just the sample data needs nothing extra:
      `Release.remove_sample_data/0` deletes their photos too.

  43. **Very large photos (e.g. 50 MP): warn first, then process them
      without slowing anyone else down** (added 2026-11-19, the
      developer's request; part of the photo speed work, step 2).
      Two things to avoid: (a) one artist's huge photo making everyone
      else wait ("better one unhappy user than many"); (b) that artist
      waiting and waiting with no clear message and no choice.
      *Today:* the browser refuses files over 25 MB; the server
      refuses photos over 52 MP (#33); anything below is processed
      like any other photo, in the same 2 limiter slots. The result is
      always ≤4096 px, so encoding costs the same as for 12 MP, but
      reading costs more: a JPEG is shrunk while it's read (cheap), a
      HEIC can't be, so all 50 MP are decoded (more CPU and memory).
      Uploading 15–25 MB on a weak phone connection can take minutes.
      Steps:
      1. **Measure** on Fly: `time_photos(count: 5, long_side: 8160)`
         (about 50 MP, JPEG: time and memory in the log lines), and a
         real 48–50 MP HEIC from the developer's phone (never put in
         the repo: phone photos carry GPS). Decide from that what
         counts as "large".
      2. **Warn, and let the artist choose**: "This photo is very large
         and will take a while to save. Choose a smaller copy, or
         continue?", with two buttons ("Choose a smaller photo" /
         "Continue with this one") and the plain-words guide from #33
         on how to make a smaller copy. The browser knows the file
         size before uploading; the pixel count the server reads from
         the header in milliseconds, before any processing, so with 3b
         (process on pick) it can ask right after the upload.
      3. **If the artist continues, process it at low priority**: e.g.
         its own limiter lane with one slot, so normal photos never
         queue behind it; big photos take turns there, with a longer
         wait allowed (no "site is busy" just for waiting in the slow
         lane); maybe fewer libvips threads for it. A clear message
         while it runs ("Your large photo is being prepared, this can
         take a few minutes"). Whether the artist may leave the page
         meanwhile depends on a real job queue (Oban, see 7a).
      Check with 3c (shrinking in the browser before upload): if the
      browser can shrink a 50 MP photo to 4096 px itself, most huge
      photos become ordinary ones and the warning is only needed when
      it can't (to check: can browsers other than Safari read HEIC?
      *Answered 2026-11-20: no; Chrome and Firefox pass HEIC on
      unshrunk, Safari on the iPhone and the Mac shrinks it*).
      **Which photos get the warning** (decided 2026-11-20, the
      developer's point): every photo over the "large" limit that
      reaches the server *unshrunk*, whatever the reason: a WebP with
      see-through parts or a moving one (3c leaves those alone), any
      PNG, TIFF or AVIF (also left alone), HEIC in browsers that can't
      read it, and photos where shrinking failed or took too long.
      The message names the reason when it's known, in plain words
      (not "complex elements"). Draft:
      "This photo is very large, and because it has see-through parts,
      it can't be made smaller on your device first. Preparing it will
      take a while." with two buttons, [Use this photo] and [Choose a
      different photo] (for a moving image: "because it's a moving
      image"). **Asked in the browser before uploading** whenever the
      browser knows the size and the reason (e.g. a see-through WebP),
      so the artist doesn't wait for a long upload first; the server
      asks after the upload only for files the browser can't read.

  44. **Tell the artist that a moving image becomes a still one**
      (added 2026-11-20). The server keeps only the first frame of a
      moving (animated) WebP, at any size: checked 2026-11-20 by
      loading a two-frame test WebP the way `Images.process_upload/3`
      does (one 1500 × 1000 frame came back). That's fine for a
      marketplace, but the artist should know, e.g. "Only the first
      picture of a moving image will be shown." Separate from the
      #43 "large" warning: it applies to small moving images too. The
      browser can tell from the file's first bytes (3c reads them for
      WebP already); GIF isn't accepted, AVIF can also be moving
      (rare). Best done with #43 or 3b, which change the upload box.







## Tech debt

- **Test emails reach the LiveView that sent them** (noted 2026-10-29,
  after updating Swoosh). Swoosh's test adapter now sends `{:email, ...}`
  to the sending process too, so the settings page tests log a
  `FunctionClauseError` from `UserLive.Settings.handle_info/2`. Tests
  pass and real mail never goes through this adapter. Fix when touching
  the settings page: e.g. a `handle_info({:email, _}, socket)` that does
  nothing, only in test, or a shared test helper.
- **Clustering before running more than one Fly Machine** (noted
  2026-10-30). PubSub (live messages, order updates, the unread dot)
  only reaches pages on the same running copy of the app. The private
  deploy runs one Machine (`fly deploy --ha=false`; Fly's default is
  two, for when the server under one fails). Before going to two or
  more (`fly scale count`), connect the Machines into a cluster:
  `DNSCluster` is in `application.ex`, and `fly launch` (2026-11-02)
  generated `rel/env.sh.eex`, which names each Machine and sets
  `DNS_CLUSTER_QUERY`, so Machines should find each other. Still to
  check when adding a second Machine: that they really connect, and
  that both share the same Erlang cookie. Otherwise a buyer and an artist on different
  Machines only see each other's messages after a reload.
- **Postgres 17 → 18: the Mac first, then the server** (noted
  2026-11-02; the developer wants it done soon, in a session of its
  own). Today: Postgres.app 2.8.5 with only 17.6 on the Mac; Fly runs
  `flyio/postgres-flex:17` (17.11 on 2026-11-03). `pg_dump` backs up
  servers of its own version or older, so a Mac on 18 can still back
  up the 17 server; the server can follow later. *2026-11-03:* the Mac
  part now waits until after the macOS upgrade, and the server part
  becomes the teardown + rebuild — see step 2 of "Order of work".
  - Mac (~30–45 min): back up the dev database with the current
    `pg_dump` (hand-made data, about 10 MB; keep a second copy), install
    the Postgres.app download with several versions (check it supports
    the new macOS), add an 18 server, create `artsy_neighbor_dev` and
    restore, run the tests, keep the 17 server stopped for a few weeks.
  - Server: create the new database on `flyio/postgres-flex:18` during
    the rebuild from `docs/deploy.md` (section 4.4 with the image tag
    changed to 18), instead of a separate dump / restore / re-attach.
  - Meanwhile, security fixes come in minor releases (17.6 → 17.7):
    update Postgres.app regularly, and update the database Machine to
    the newest 17.x image with `fly image update -a <app>-db` (restarts
    the database briefly; not yet tried).
- **Keep Elixir, Erlang and the libraries current** (noted 2026-10-29).
  The Mac (Homebrew) and the `Dockerfile` must use the same Elixir and
  Erlang versions; check both when updating. `mix hex.outdated` lists
  library updates; Docker Hub's `hexpm/elixir` tags list the images.

- **Flag-cleanup delete paths have a narrow race** — every hard delete
  that cleans up `Flag` rows goes through `ArtsyNeighbor.HardDelete`
  (Phase 6 of the entity-removal pass; it used to be hand-copied 3x). It
  row-locks the entity, but `Flag` has no FK for that lock to block, so a
  `Flag` inserted between the flag cleanup and the entity delete can
  outlive the entity it references.
- **FK cascade + remove_entity() rollout is still partial** — only Artist
  has real FK cascades; Product has its own soft-delete but its
  dependents (`product_reviews`, etc.) aren't cascaded yet.
- **`deactivate_artist/1`/`update_artist/2` cascade off a stale in-memory
  struct, not a locked DB read** — a narrower version of the same TOCTOU
  race `hard_delete_artist/1` already closes with `SELECT ... FOR UPDATE`.
  `restore_product/1` has a similar narrower check-then-act gap. Low
  severity today; noted during the entity-removal-consistency pass,
  not fixed.
- **Nullable bio/medium** on Artist — revisit when ready.
- **Unread badge implementation** — works, but has some complexity worth
  revisiting eventually. Do NOT refactor until explicitly asked.
- **Nav UI** — top strip cuts off on small screens; arrow visibility needs
  a JS scroll listener. Deferred until closer to deployment.
- **Product pictures not visible without scrolling**: this is the case for the Artist show page both on the desktop but especially brutal on the phone. On the desktop at least about 2/3 of the product row is showing while on the phone no products are visible at all. We need to make products appear higher. I am contemplating a collapsible panel that would hide/show filters, reviews, delivery into and categories. This may be not ideal as that infor too is important. At least on the phones we may consider seriously trimming the header of the Artist show page. On the desktop too we may need to arrange all this info in at most one thin line.

