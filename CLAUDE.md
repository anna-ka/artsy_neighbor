# Artsy Neighbor

## What this is

A Phoenix LiveView app for a **local art marketplace**: independent artists (vendors)
set up a public profile and product catalog, local buyers browse and order, pickup
(or eventually delivery) gets arranged directly between buyer and vendor, and after
the order completes both sides can leave reviews. Think "farmers market for art,"
online.

For now, it is designed for one city: Victoria, BC. But the hope is to have multiple independent instances running 
in various cities in Canada.

Victoria's population skews older: many artists on the site will be over
60, a good share over 50, and likely most over 40. UI should be intuitive
and easy rather than flashy — see the design principles under step 1 of
"Order of work" in `NOTES.md`.

The developer working on this project is a professional researcher in natural
language processing, not a professional software developer. She understands
programming well, but this is her first web dev project and her first Elixir and
Phoenix project. She relies on Claude for guidance on architecture, security,
workflow, and coding style. For any such guidance, suggest it and ask her to
confirm before acting on it.

This shapes a few things worth keeping in mind while working on it:

- **Vendors are individuals, not companies.** Products, pricing, and availability
  are set by the artist themselves through `/vendor/*`. There's no multi-seat
  vendor accounts.
- **Trust is local and asymmetric.** Buyer and vendor coordinate pickup logistics
  through a real conversation thread tied to the order, not just a status field —
  see Order Flow below.
- **Removal is usually soft.** An artist or product going away shouldn't retroactively
  break past orders/reviews, so the default is to hide (`:inactive` / `:removed` /
  `:unavailable` / `:archived`), not delete. Hard delete exists only as an explicit admin/testing
  action — see `Artists.hard_delete_artist/1`. The convention (rolled out in
  `docs/plans/2026-09-17-entity-removal-consistency.md`): an entity gets
  `soft_delete_<entity>/1` (default, reversible — usually paired with
  `restore_<entity>/1`) and, where a hard path is kept at all,
  `hard_delete_<entity>/1` (rare, admin/testing-only, irreversible). Hard
  deletes that must also clean up polymorphic `Flag` rows go through the shared
  `ArtsyNeighbor.HardDelete.delete_with_flags/2` (`lib/artsy_neighbor/hard_delete.ex`),
  which also deletes the photo files of image rows that go with it.
  Anything that deletes an image row must delete its files after the
  commit (`Images.delete_files/1`, or `Images.delete_files_of_deleted_row/1`
  on a single delete's result); soft deletes keep the files.
  User is the exception so far: it has a status field but no removal functions
  (see the User schema note below).
- **Payments aren't live yet.** Right now this is cash/Interac-at-pickup in design;
  Stripe-shaped functions are stubbed with `Logger` calls until that's wired in.

## Roles & routing

- Public (no auth) — browse artists/products, `/artist/:id`, `/artist/:id/store`
- `:vendor` — an authenticated user with an artist profile → `/vendor/*`
  (dashboard, product management, profile, sales/orders)
- Buyer — any authenticated user, not a distinct role → `/orders/*`
- `:admin` → `/admin/*` (artist/product/category management, moderation)

Router: `lib/artsy_neighbor_web/router.ex`

## Stack

Elixir 1.20 / Erlang 29, Phoenix 1.8 + LiveView 1.2, Postgres (`ecto_sql`), Tailwind + esbuild for assets,
Swoosh for mail (not yet sending anything real), Argon2 for password hashing,
Bandit as the web server. No JS framework — LiveView + a little JS hooks where
needed.

## Commands

```
mix setup              # deps, db create+migrate+seed, assets
mix test                # runs ecto.create/migrate --quiet first, then the suite
mix precommit           # compile --warnings-as-errors, deps.unlock --unused, format, test — run before committing
mix phx.server           # dev server
```

## Key file paths

- Router: `lib/artsy_neighbor_web/router.ex`
- Contexts: `lib/artsy_neighbor/{artists,products,orders,reviews,conversations}.ex`
- Vendor dashboard: `lib/artsy_neighbor_web/live/vendor_live/dashboard.ex`
- Vendor product form: `lib/artsy_neighbor_web/live/vendor_live/product_form.ex`
- Vendor profile form: `lib/artsy_neighbor_web/live/vendor_live/profile/form.ex`
- Vendor sales: `lib/artsy_neighbor_web/live/vendor_live/orders_index.ex`,
  `orders_show.ex`
- Artist public pages: `lib/artsy_neighbor_web/live/artist_live/show.ex`, `store.ex`
- Buyer order history: `lib/artsy_neighbor_web/live/order_live/index.ex`, `detail.ex`
- Admin artist management: `lib/artsy_neighbor_web/live/admin_artist_live/index.ex`
- Layouts: `lib/artsy_neighbor_web/components/layouts.ex`
- Photos: `lib/artsy_neighbor/images.ex` (check, resize, store; `Images.url/2`),
  `lib/artsy_neighbor/storage.ex` + `storage/local.ex`,
  `lib/artsy_neighbor/images/limiter.ex`,
  `lib/artsy_neighbor/images/prepared_folders.ex` (temporary folders of
  photos checked on pick, deleted when the page closes); form side:
  `lib/artsy_neighbor_web/photo_uploads.ex`, plus the browser hook that
  shrinks big photos before upload, `assets/js/photo_shrink.js`. Plans:
  `docs/plans/2026-10-28-image-storage-and-resizing.md`,
  `docs/plans/2026-11-19-browser-shrinking-and-early-processing.md`
- Sample data (dev seeds and the Fly preview): `lib/artsy_neighbor/sample_data.ex`
  (add-only, photos through `Images.process_upload/3`), the data in
  `priv/repo/sample_data/*.exs`; `seeds.exs` wipes first and then uses it,
  `demo_data.exs` adds only the demo artists, on Fly
  `Release.add_sample_data/0`; `remove_sample_data/0` and
  `check_before_launch/0` take it away again (`docs/deploy.md` §5.1)
- Uploads (dev only — see `NOTES.md`): public sizes in
  `priv/static/uploads/{products,artists}/`, private `source.webp` in
  `priv/private_uploads/`; older uploads/seed images in
  `priv/static/uploads/` and `priv/static/images/`

## Conventions

### Code style

Because the developer is new to Elixir and web programming (see above),
favor explicit, readable code over dense/clever one-liners as long as it
doesn't cost real efficiency.

- Avoid `&`-capture shorthand for anonymous functions (e.g.
  `&Map.get(attrs, &1)`, `&is_nil/1`). Prefer a named `fn x -> ... end`
  body, or a small named helper function, so the reader doesn't have to
  mentally expand the shorthand.
- Abstractions are OK, but dense syntax is not desirable. Elaborate
  abstractions merit a comment.

- Layout variant string: `"public"` | `"admin"` | `"vendor"` — passed to
  `Layouts.artsy_main`.
- `current_scope.artist` is the logged-in vendor's artist profile;
  `current_scope.user` is the underlying user. A user only has an `artist` once
  they've onboarded as a vendor.
- `artist_id` is always injected server-side in vendor forms from
  `current_scope.artist` — never trust an `artist_id` coming from params.
  Likewise an artist profile's owner (`user_id`) and onboarding state are
  never cast by the vendor changesets; see Artist below.
- The `Orders` functions that change an order take the caller's
  `current_scope` as their first argument and work out the role
  (buyer / vendor / admin) themselves, refusing anyone else with
  `{:error, :unauthorized}`. Never pass a role in. See "Who is acting"
  at the top of `lib/artsy_neighbor/orders.ex`.
- `Products` works the same way for every change to a work, its photos
  or a collection: the scope comes first, and the role is the owner
  (the scope's artist profile) or an admin. An owner whose profile is
  `:removed` gets `{:error, :artist_removed}` (they can still see their
  works). The check uses the row as it is now, locked in the change's
  own transaction, never the struct the page passed in (it may be
  stale); something deleted meanwhile gives `{:error, :not_found}`.
  Vendor pages look things up with `Products.get_own_product/2`
  and `get_own_collection/2` (nil for someone else's) and parse ids
  with `ArtsyNeighborWeb.Params.parse_id/1`, never `String.to_integer`.
  `AdminProducts` refuses non-admins too. See "Who is acting" at the top
  of `lib/artsy_neighbor/products.ex`.
- Public queries for artists/products/categories always filter by status — see
  `Artists.filter_artists/1`, `Artists.list_artists/0`,
  `Products.only_available/1`, `Categories.list_categories/0`. There is no
  "all statuses" query without an explicit admin-only function name
  (`list_<entity>_all_status/0`). Contexts with a status field also expose a
  composable `with_status(query, status)` filter (`nil` = no filter).
- Back navigation uses `return_to` + `return_label` query params rather than
  browser history.
- `ProductImage` / `ArtistImage` field is `path`, not `url`. It holds either an
  old-style web path starting with `/` or a storage key (a folder of sizes).
  Never put it in `src=` directly: always `Images.url(image.path, size)` with
  `:thumb` (cards, lists, small photos), `:medium` (product page photo) or
  `:large` (large view) — see step 3 of the image plan for which size where.
  For "the cover photo" of a product or artist use
  `Images.first_url(images, size, placeholder)` (sorts by `position`), not
  `List.first`. A test (`image_display_test.exs`) fails on any `.path` in
  `lib/artsy_neighbor_web` without `Images.url(`.
- **Placeholders are a display choice, not data.** When something has no
  picture, store `nil` (or no image row), never the placeholder's path. Pages
  pick the placeholder when they draw the picture, with
  `Images.placeholder(:artist | :product | :category)` or
  `Images.or_placeholder(path, kind)`; never write a placeholder path in a
  page. That way changing a placeholder never needs a database update.
  New photos only go in through `Images`, never by copying the uploaded
  file: the forms (via `PhotoUploads`) use its two halves,
  `Images.prepare_upload/4` when a photo has uploaded and
  `Images.store_prepared/2` at Save; everything else (sample data, the
  timing tool) uses `Images.process_upload/3`, which is both together.

## Git and GitHub

- Claude commits only after an explicit request or approval, and never
  pushes to a remote — pushing is always done by the developer.
- Claude drafts each commit message in `COMMIT_MSG.txt` at the repo root
  (gitignored, overwritten for every commit). The developer reviews/edits
  it there; on approval Claude commits with `git commit -F COMMIT_MSG.txt`.

### Commit message style

Commit messages should be easy to skim and read like plain prose, not
pseudocode.

- **Line 1: a headline** that makes sense on its own, in the past tense,
  ~70 characters max. It's what `git log --oneline` and GitHub show.
- **`SUMMARY:` block**: 1–8 short lines giving the overview of the commit.
- **Then one block per area of work** (a file, context, or feature), each
  with a short label and hyphenated items.
- Past tense, short sentences, lines wrapped at ~72 characters.
- The `Co-Authored-By:` trailer, when used, goes last.

Example:

```
Added the agreed order of work to NOTES.md and Git rules to CLAUDE.md

SUMMARY:
- Recorded the plan for what to build next, in order.
- Wrote down the Git workflow: commit only on approval, never push.

NOTES.md:
- Added an "Order of work" section.
- Added new backlog items.

.gitignore:
- Ignored COMMIT_MSG.txt.
```

## Schemas (key fields)

**Artist** (`lib/artsy_neighbor/artists/artist.ex`)
- `status` — `:active` | `:inactive` | `:removed`, default `:inactive`;
  `status_changed_at` auto-set on change
- `delivery_options` — `{:array, :string}`, default `["pickup"]`;
  `delivery_info` — map, keys match `delivery_options`, values are note strings
- `onboarding_complete` — bool, set true on final profile save
- `homepage`, `instagram`, `facebook` — optional URL strings
- Four changesets: `registration_changeset` (step 1 only), `activation_changeset`
  (full profile), `admin_changeset` (full profile + owner), `status_changeset`
  (status only). The vendor-facing two do NOT cast `status`, `user_id`,
  `onboarding_step` or `onboarding_complete`: the server sets those
  (owner on the struct, onboarding with `put_change`). Only
  `admin_changeset` takes `user_id`, used only through `AdminArtists`
  (the admin form, test fixtures). `Artists.create_artist/1` takes a
  changeset only; creating a profile from a map of params with an owner
  is `AdminArtists.create_artist/1`. Never give either a vendor form's
  params.
- One profile per user: `artists.user_id` is a unique index (several
  `NULL`s are allowed). `Artists.get_artist_by_user_id/1` runs on every
  request (`Accounts.Scope`) and would crash on a duplicate.
- Status changes go through `Artists` functions, not `update_artist/2`:
  `activate_artist/1` (refused without a profile photo),
  `deactivate_artist/1`, `soft_delete_artist/1`, or the dispatcher
  `change_status/2` (used by the admin form). Removing the last photo of an
  `:active` artist is refused.
- `filter_artists/1` and `list_artists/0` always scope to `status: :active`;
  `list_artists_all_status/0` is the admin-only escape hatch — all statuses,
  sorted active → inactive → removed, then nickname

**Product** (`lib/artsy_neighbor/products/product.ex`)
- `status` — `:draft` | `:available` | `:unavailable` | `:archived`, default
  `:draft`. `Product.changeset` does NOT cast `status`; only
  `publish_product/2`, `soft_delete_product/2`, `restore_product/2` and
  `delete_product_image/2` change it. A product needs at least one photo to be
  `:available`; removing its last photo moves it back to `:draft`.
- Owner: `Product.changeset` does NOT cast `artist_id` either.
  `Products.create_product/2` takes the owner from the scope
  (`scope.artist`); `update_product/3` never changes it. Only
  `Product.admin_changeset/2` takes it, used only through
  `AdminProducts` (the admin product form). Both go through
  `Products.save_product/1`, which puts a product with no collection
  into the default one and refuses another artist's collection.
- Positions: `Product.changeset` doesn't cast `position`, and
  `ProductImage.changeset` doesn't cast `product_id` (set on the
  struct). Reordering goes through the `swap_*_positions/3` functions
  and each schema's `position_changeset/2`.
- When an artist is soft-deleted (`Artists.soft_delete_artist/1`), all their
  products go `:archived` — not deleted, and unconditionally (even ones
  already `:archived` individually). When an artist transitions from
  `:active` to `:inactive` — only ever through `Artists.deactivate_artist/1`,
  which the vendor dashboard's toggle calls directly and the admin edit
  form's status dropdown reaches through `Artists.change_status/2`
  (`Artists.update_artist/2` never changes the status) — only their
  `:available` products go `:unavailable`, a lighter, reversible-in-spirit
  pause that leaves already-`:archived` products alone. Neither
  transition reverses automatically — restoring the artist doesn't restore
  their products; that's a separate, still-manual step
  (`Products.restore_product/2`, itself gated on the artist being `:active`).
- `only_available/1` requires `status == :available`, `artist_id` not nil,
  AND the owning artist's own `status == :active` (checked via a subquery,
  not a join, since callers sometimes already join `:artist` themselves) —
  this is deliberately redundant with the cascades above (defense in
  depth): even if some write path sets a product `:available` without going
  through the dedicated cascade/guard functions, it still won't surface
  publicly with a non-`:active` artist attached.

**Category** (`lib/artsy_neighbor/categories/categories/category.ex`)
- `status` — `:active` | `:archived`, default `:active`
- `list_categories/0` and `list_categories_ordered_by_time/0` scope to
  `:active`; `list_categories_all_status/0` is the admin escape hatch
- `soft_delete_category/1` / `restore_category/1`; `AdminCategories.hard_delete_category/1`
  is a plain delete (`products.category_id` is `on_delete: :nilify_all`, and
  categories can't be flagged, so no flag cleanup is needed)

**ProductCollection** (`lib/artsy_neighbor/products/product_collection.ex`)
- `is_default` — every artist has exactly one default collection (made
  with the profile; a unique index allows only one), where works with
  no other collection go. It always comes last, on the dashboard and
  on the public pages. Recognise it by `is_default`, never by
  its name: it starts as "Uncategorized" but may be renamed. It can't be
  deleted (`Products.delete_collection/2` refuses it).
- The changeset takes only `name`; `Products.create_collection/2` takes
  the owner from the scope and works out the position. Reordering
  goes through `position_changeset/2`.

**Conversations** — `buyer_id`/`artist_id` are nullable (see migration
`20260817000002_allow_null_participants_in_conversations`) because system
messages need both to be nil.
- `status` — `:active` | `:archived`, default `:active`. Every
  `list_conversations_for_*` and unread-count query scopes to `:active`, so an
  archived thread doesn't keep surfacing the unread dot.
  `soft_delete_conversation/1` / `restore_conversation/1`;
  `hard_delete_conversation_dev/1` isn't compiled into `:prod` builds.

**ConversationEvent** (messages and order status-change events)
- `status` — `:active` | `:deleted`, default `:active`
- `Conversations.soft_delete_event/2` only works on `event_type: :message`
  rows, and only for the user who sent them; `:status_change` events are the
  order's audit trail and are never deletable. A deleted message renders as
  a "message deleted" placeholder (see `ConversationLive.Show`) rather than
  disappearing, so replies keep their context.

**Order** — full state machine and the conversation/token mechanics around pickup
scheduling are nontrivial enough to warrant their own read: see
`lib/artsy_neighbor/orders.ex` and `lib/artsy_neighbor/orders/order.ex` directly,
and the order tests (`test/artsy_neighbor/orders_test.exs`) for how state
transitions are actually expected to behave — an order can be confirmed or not,
have a pickup scheduled/rescheduled or not, and have a pickup token issued or not,
somewhat independently, so don't assume a status field alone tells you what's
allowed.

**Reviews** — three kinds tied to an order: vendor review, buyer review,
per-product review, each within a 14-day window of order completion. See
`lib/artsy_neighbor/reviews.ex`.
- `status` — `:active` | `:removed`, default `:active`, on all three schemas.
  Visibility checks and the per-order getters only see `:active` reviews.
- `soft_delete_*_review/2` is the normal delete; `hard_delete_*_review/1` is
  the exceptional one (via `HardDelete`, cleans up flags on the review).
- Re-submitting after a soft delete **revives** the existing `:removed` row
  instead of inserting a new one (the unique index on `order_id`, or
  `order_id`+`product_id` for product reviews, would otherwise block it) — see `create_or_revive_review/3`.

**User** (`lib/artsy_neighbor/accounts/user.ex`)
- `status` — `:active` | `:suspended` | `:removed`, default `:active`;
  `status_changed_at` auto-set on change; `status_changeset/2`
- **Schema-only for now.** Nothing sets or enforces it: a non-`:active` user can
  still log in, and there are no `soft_delete_user`/`hard_delete_user`
  functions. Several FKs to `users` (`orders.buyer_id`, the review
  `reviewer_id`s, `flags.reporter_id`, plus the polymorphic `"buyer"` flag
  subject) each need a product decision first. The likely future direction is
  anonymization, not hard delete — see `NOTES.md`.
- `Accounts.list_users/0` returns all statuses (users are never listed
  publicly), sorted active → suspended → removed, then username.

## Known issues, deferred work, backlog

All of it lives in **`NOTES.md`** at the repo root, not here. It has sections
for known bugs, known limitations / deliberately deferred design choices
(dev-only upload storage, no real payments, schema-only delivery, the
unfinished flag-moderation UI, ...), small deferred follow-ups, the next
feature chunks, and tech debt. Read it before starting a new piece of work,
and update it directly (add, edit, or delete bullets) as things change.

