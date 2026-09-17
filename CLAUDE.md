# Artsy Neighbor

## What this is

A Phoenix LiveView app for a **local art marketplace**: independent artists (vendors)
set up a public profile and product catalog, local buyers browse and order, pickup
(or eventually delivery) gets arranged directly between buyer and vendor, and after
the order completes both sides can leave reviews. Think "farmers market for art,"
online.

For now, it is designed for one city. But the hope is to have multiple independent instances running 
in various cities in Canada.

This shapes a few things worth keeping in mind while working on it:

- **Vendors are individuals, not companies.** Products, pricing, and availability
  are set by the artist themselves through `/vendor/*`. There's no multi-seat
  vendor accounts.
- **Trust is local and asymmetric.** Buyer and vendor coordinate pickup logistics
  through a real conversation thread tied to the order, not just a status field —
  see Order Flow below.
- **Removal is usually soft.** An artist or product going away shouldn't retroactively
  break past orders/reviews, so the default is to hide (`:inactive` / `:removed` /
  `:unavailable`), not delete. Hard delete exists only as an explicit admin/testing
  action — see `Artists.delete_artist/1`.
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
- Uploads (dev only — see Known issues): `priv/static/uploads/{products,artist_profiles}/`

## Conventions

- Layout variant string: `"public"` | `"admin"` | `"vendor"` — passed to
  `Layouts.artsy_main`.
- `current_scope.artist` is the logged-in vendor's artist profile;
  `current_scope.user` is the underlying user. A user only has an `artist` once
  they've onboarded as a vendor.
- `artist_id` is always injected server-side in vendor forms from
  `current_scope.artist` — never trust an `artist_id` coming from params.
- Public queries for artists/products always filter by status — see
  `Artists.filter_artists/1`, `Artists.list_artists/0`,
  `Products.only_available/1`. There is no "all artists/products" query without
  an explicit admin-only function name.
- Back navigation uses `return_to` + `return_label` query params rather than
  browser history.
- `ProductImage` field is `path`, not `url`.

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
- When an artist is removed, their products go `:unavailable` — not deleted
- `only_available/1` requires both `status == :available` AND `artist_id` not nil

**Conversations** — `buyer_id`/`artist_id` are nullable (see migration
`20260817000002_allow_null_participants_in_conversations`) because system
messages need both to be nil.

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

## Known issues / deliberately deferred

- **Upload storage is dev-only.** Files land in `priv/static/uploads/`, which is
  wiped on deploy. Needs S3/ex_aws, Tigris, or Cloudinary before shipping —
  Waffle is a good fit for the upload-handling layer.
- **Upload filenames** use `System.unique_integer` in
  `vendor_live/product_form.ex`, which resets across restarts — fine for dev,
  should become `Ecto.UUID.generate()` before this matters.
- **Delivery as a fulfillment method is schema-only.** `delivery_options` can
  contain `"delivery"` but nothing in the UI lets a buyer choose it, and
  `complete_pickup/2` has no delivery clause. Not planned for initial launch.
- **No real payment processing yet.** Charge/refund functions are `Logger`
  stubs; a `payment_method` field (cash/Interac) is planned but not yet on the
  `Order` schema.
- **Flagging: reporting works for vendors/products/buyers; reviews and
  admin moderation don't yet.** Buyers/vendors can report a rogue vendor,
  product, or buyer via `/flag/:subject_type/:subject_id` (`FlagLive.New`)
  — see `Reviews.resolve_subject/2` and `Reviews.create_flag/1`.
  `resolve_subject/2` also handles the three `*_review_of` types
  (flagging a review itself), but nothing in the UI links to them yet,
  because reviews aren't shown publicly anywhere today — only to the two
  parties on an order, on their own private pages. A future UI pass needs
  to cover, together: a public reviews display, "flag this review" entry
  points once that exists, and the `/admin/flags` moderation view
  (review/resolve/dismiss reports) — plus notifying a reporter when their
  flag's status changes, which depends on that moderation view existing.


