# Artsy Neighbor

## What this is

A Phoenix LiveView app for a **local art marketplace**: independent artists (vendors)
set up a public profile and product catalog, local buyers browse and order, pickup
(or eventually delivery) gets arranged directly between buyer and vendor, and after
the order completes both sides can leave reviews. Think "farmers market for art,"
online.

For now, it is designed for one city. But the hope is to have multiple independent instances running 
in various cities in Canada.

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
  `ArtsyNeighbor.HardDelete.delete_with_flags/2` (`lib/artsy_neighbor/hard_delete.ex`).
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

Phoenix 1.8 + LiveView 1.1, Postgres (`ecto_sql`), Tailwind + esbuild for assets,
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
- Uploads (dev only — see `NOTES.md`): `priv/static/uploads/{products,artist_profiles}/`

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
- Public queries for artists/products/categories always filter by status — see
  `Artists.filter_artists/1`, `Artists.list_artists/0`,
  `Products.only_available/1`, `Categories.list_categories/0`. There is no
  "all statuses" query without an explicit admin-only function name
  (`list_<entity>_all_status/0`). Contexts with a status field also expose a
  composable `with_status(query, status)` filter (`nil` = no filter).
- Back navigation uses `return_to` + `return_label` query params rather than
  browser history.
- `ProductImage` field is `path`, not `url`.

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
- Three changesets: `registration_changeset` (step 1 only), `activation_changeset`
  (full profile), `status_changeset` (status only)
- `filter_artists/1` and `list_artists/0` always scope to `status: :active`;
  `list_artists_all_status/0` is the admin-only escape hatch — all statuses,
  sorted active → inactive → removed, then nickname

**Product** (`lib/artsy_neighbor/products/product.ex`)
- `status` — `:available` | `:unavailable` | `:archived`, default `:available`
- When an artist is soft-deleted (`Artists.soft_delete_artist/1`), all their
  products go `:archived` — not deleted, and unconditionally (even ones
  already `:archived` individually). When an artist transitions from
  `:active` to `:inactive` — via `Artists.deactivate_artist/1` (the vendor
  dashboard's own toggle) or via the general `Artists.update_artist/2`
  (e.g. the admin edit form's own status dropdown) — only their
  `:available` products go `:unavailable`, a lighter, reversible-in-spirit
  pause that leaves already-`:archived` products alone. Both functions
  share this cascade so it holds regardless of entry point. Neither
  transition reverses automatically — restoring the artist doesn't restore
  their products; that's a separate, still-manual step
  (`Products.restore_product/1`, itself gated on the artist being `:active`).
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

