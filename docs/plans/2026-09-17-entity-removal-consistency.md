# Plan — consistent soft-removal across all entities

**Status as of 2026-09-17:** Phase 0 in progress (leak fix + crash-guard fix
written, reviewed, not yet committed). Phases 1–7 not started.

**Origin:** planned via Claude Code's Plan Mode on 2026-09-17, after a
codebase-wide audit (three parallel Explore passes over entity schemas,
context functions, public/admin query filtering, and FK/association
dependencies) found that only Artist and Product actually follow the
soft-delete principle `CLAUDE.md` already states. Landed as one phase = one
or a few commits per entity, each reviewed via `/code-review` before
committing, matching this project's established review-before-commit
convention (see the two `docs/code-reviews/` entries this plan itself
references).

## Context

Only **Artist** and **Product** currently follow the principle stated in
`CLAUDE.md` ("Removal is usually soft... Hard delete exists only as an
explicit admin/testing action"): a `status` enum, public queries that filter
it out, and an admin escape hatch to see everything. Every other entity is
inconsistent with that principle in its own way — **Category** and
**Conversation** have no status concept and only a bare hard `Repo.delete`,
**Review** hard-deletes on every "delete" action (time-boxed, but still a
real delete), **ConversationEvent** (chat messages) can't be deleted by
their author at all today, **User** has no removal story at all, and even
Artist/Product themselves are missing a restore/unarchive path despite their
3-state enum implying one should exist. A pre-existing bug compounded this:
`ProductLive.Show` (`/products/:id`) never checked `Product.status`, so an
archived product was still fully visible by direct URL despite being hidden
from every list view (fixed in Phase 0).

The goal of this pass is to bring every entity that represents a removable
"thing" (not a workflow-state or log entity) up to the same standard:
soft-status by default, hard-delete only as a narrow, explicitly-named
exception, invisible-to-the-public-by-default, admin-visible-on-request.
This lands as one phase = one or a few commits per entity, in dependency
order, so the shared pieces (the admin UI component, the hard-delete helper)
get extracted only once there are enough real examples to generalize from —
not before, not after most entities have already re-copied the
un-extracted version.

**Naming convention (applies across every phase, including a rename of
existing code):** standardize every soft-removal function as
`soft_delete_<entity>/1` and every hard-removal function as
`hard_delete_<entity>/1`, replacing the current inconsistent
`remove_*`/`delete_*`/`archive_*` naming. `restore_<entity>/1` is the paired
"undo a soft_delete" name. This means renaming the two functions that
already exist under the old names — `Artists.remove_artist/1` →
`soft_delete_artist/1`, `Artists.delete_artist/1` → `hard_delete_artist/1`,
`Products.remove_product/1` → `soft_delete_product/1`,
`Products.delete_product/1` → `hard_delete_product/1` — including all call
sites (LiveViews, tests), as part of Phase 1 below, so every later phase can
be written against the new convention from the start instead of introducing
it partway through.

**Decisions made while planning:**
- Review deletion becomes soft (status field), not just hard-delete-within-
  a-window.
- **ConversationEvent (chat messages) is in scope**: a person can delete a
  message they sent. Only `event_type: :message` rows are deletable this
  way — `:status_change` events are the order's audit trail and must stay
  intact.
- User gets a schema-only phase this pass — no enforcement, no FK
  rewiring, no hard-delete. Real wiring is a separate future plan.
- Conversation gets the schema/context/query-filtering, but **no** new
  `/admin/conversations` screen this pass — that's out of scope, deferred.
- **Order and Flag's own status field are explicitly excluded** from
  getting a "removed/archived" status: Order's status is a workflow state
  machine where records must never disappear; Flag's
  `:pending/:reviewed/:dismissed` is a moderation lifecycle, not an
  entity-removal concept — conflating it with "removed" would be a
  modeling mistake.

## Reference pattern (already built — every phase below extends this,
under the new naming)

- **Artist** (`lib/artsy_neighbor/artists/artist.ex`, `artists.ex`):
  `status` enum `:active|:inactive|:removed`, `status_changed_at`
  auto-stamped, `status_changeset/2`. Soft/hard functions being renamed per
  above. Hard-delete: `Ecto.Multi`, row-locked `FOR UPDATE`, hand-cleans
  polymorphic `Flag` rows, `rescue [Ecto.ConstraintError, Postgrex.Error]`.
  Public queries always filter via `with_status/2`;
  `list_artists_all_status/0` is the admin escape hatch.
- **Product** (`lib/artsy_neighbor/products/product.ex`, `products.ex`):
  `status` enum `:available|:unavailable|:archived`. Soft/hard functions
  being renamed per above; hard-delete **not** row-locked yet —
  known/deferred gap, closed in Phase 6. `only_available/1` is the private
  filter; `filter_products_all_status/1` is the admin escape hatch.
- **Admin UI**: `AdminArtistLive.Index` / `AdminProductLive.Index` —
  hand-copied twins today. List-all-status query, status column, two-tier
  `data-confirm`'d actions (soft = `text-warning`, hard = `text-error`),
  `{:ok,_}/{:error,_}` handled with a flash.

## Phase 0 — Fix the `ProductLive.Show` leak (hotfix)

No schema change. `Products.get_product_with_associations/1` was called by
**both** the public `ProductLive.Show` and the admin `AdminProductLive.Show`
— it couldn't just be filtered in place. Added
`get_product_with_associations_all_status/1` (mirrors the `_all_status`
naming convention) for the admin view, and filtered the existing
`get_product_with_associations/1` to
`status == :available and not is_nil(artist_id)` (same predicate as
`only_available/1`) for the public one. The existing `nil ->` branch in
`ProductLive.Show.handle_params/3` already redirected with a flash — no new
UI code needed there.

**Commit:** 1, small, standalone bug fix.

**`/code-review` finding fixed in the same commit:** the admin show
template rendered `@product.artist.nickname` unguarded — pre-existing (the
function this was copied from had the same gap), narrowed rather than
introduced by this phase (the public path is now protected via
`only_available/1`; only the admin path's direct-URL edge case remained).
Fixed by rendering "No artist (orphaned product)" instead of crashing.

## Phase 1 — Rename to soft_delete/hard_delete, and retrofit restore onto
Artist + Product

1. **Rename commit:** `Artists.remove_artist/1` → `soft_delete_artist/1`,
   `Artists.delete_artist/1` → `hard_delete_artist/1`,
   `Products.remove_product/1` → `soft_delete_product/1`,
   `Products.delete_product/1` → `hard_delete_product/1`. Update every call
   site: the two admin index LiveViews, the vendor dashboard's own archive
   action, and all existing tests referencing the old names. Pure rename,
   no behavior change — verified by the existing test suite passing
   unchanged (once renamed).
2. **Restore commit:** Add `Artists.restore_artist/1` (status →
   `:inactive`, not `:active` — restoring shouldn't silently re-publish a
   profile; the vendor still has to re-activate) and
   `Products.restore_product/1` (status → `:available`). Both reuse the
   existing `status_changeset/2`. Fix the admin "soft-delete" confirm copy
   on Artist (currently implies a restore path that doesn't exist) now
   that one does.
3. **Admin UI commit:** Add a third ("restore") action to
   `AdminArtistLive.Index` / `AdminProductLive.Index`, shown only for
   non-active rows — still hand-copied here on purpose, since Phase 2 is
   where extraction happens.

**Commits:** 3.

## Phase 2 — Extract the shared admin status-column + action-button
component

With Artist and Product now both at three tiers (restore / soft_delete /
hard_delete) and near-identical markup, extract a function component (e.g.
`status_actions/1` in a shared components module) for the status column +
confirm-gated action buttons. Refactor both admin index LiveViews to use
it — pure refactor, existing tests should pass unchanged. Placed here
deliberately: two real examples exist (enough to know what varies), and
Category/Conversation admin screens haven't been built yet.

**Commit:** 1.

## Phase 3 — Category gets status

Add `status` (`:active | :archived`, default `:active`) + `status_changeset/2`
to `Category` (currently has no status field at all — see
`lib/artsy_neighbor/categories/categories/category.ex`). Add
`Categories.soft_delete_category/1`, `restore_category/1`, `with_status/2`,
and `list_categories_all_status/0` (admin escape hatch); scope
`list_categories/0` / `list_categories_ordered_by_time/0` to `:active`.
Rename the existing `AdminCategories.delete_category/1` (currently a bare
`Repo.delete`) to `hard_delete_category/1`, kept as the demoted, exceptional
action — since `products.category_id` is `on_delete: :nilify_all` and
Category is never a `Flag.subject_type`, this stays low-risk and does
**not** need the Multi+rescue+flag-cleanup treatment.

Note the blast radius here is wider than Artist/Product had:
`list_categories/0` is currently called unfiltered from ~9 sites (nav bar,
home, product index/filter, vendor product form, artist store, both admin
product LiveViews, admin dashboard category count). Only the admin call
sites need to switch to the new all-status function; the rest already want
active-only and get it for free once the default is scoped.

Admin UI: `AdminCategoryLive.Index` status column/actions built directly on
the Phase 2 shared component (first real reuse).

**Commits:** 3 (schema+context; the ~9 call-site audit/update; admin UI).

## Phase 4 — Review gets status (soft_delete replaces default hard-delete)

`VendorReview`/`BuyerReview`/`ProductReview` currently have no status
field — "deletion" is `delete_vendor_review/2` etc. → shared private
`delete_reviewed_with_flags/2`, a real `Repo.delete`, gated by
`within_edit_window?/1` unless `opts[:admin]`. Add `status`
(`:active | :removed`) + `status_changeset/2` to all three schemas. Rename
the day-to-day delete path to `soft_delete_vendor_review/2` etc. and change
it to a status update instead of a hard delete. Update `review_visible?/3`
(the existing time-window/reciprocity visibility check) to also require
`status == :active`.

Keep the hard-delete path too, renamed `hard_delete_vendor_review/2` etc.
(backed by the existing `delete_reviewed_with_flags/2` shared helper), for
the genuine exceptional case (dev/testing, or content an admin wants truly
gone, not just hidden) — same "hard delete is the exception" shape as
everywhere else.

No dedicated admin review-management screen exists yet (`/admin/reviews` is
separately known-missing per `CLAUDE.md`'s Known Issues, bundled with the
future flags-moderation pass) — this phase does not build one; it only
makes the underlying delete/visibility behavior consistent.

**Commits:** 2 (schema+status field across the 3 schemas as one; context
renames/changes + `review_visible?/3` update as one).

## Phase 5 — Conversation + ConversationEvent (messages) get status

**Conversation:** add `status` (`:active | :archived`) + `status_changeset/2`
to `Conversation` (currently none — see
`lib/artsy_neighbor/conversations/conversation.ex`). Rationale: admins need
a way to hide/mute a spam or abusive thread without destroying message
history a moderation review might need. Add
`Conversations.soft_delete_conversation/1`, `restore_conversation/1`. Scope
`list_conversations_for_buyer/1`, `list_conversations_for_artist/1`,
`list_conversations_for_user/1`, and the unread-count queries to
`status: :active` — otherwise an archived thread could still surface an
unread badge. Rename `delete_conversation_dev/1` →
`hard_delete_conversation_dev/1` and make its "DEV ONLY" doc comment
literal — gate it so it only works outside `:prod`.

**ConversationEvent (messages):** add `status` (`:active | :deleted`,
default `:active`) + a changeset to `ConversationEvent`. Add
`Conversations.soft_delete_event/1` (or `/2` if it needs an actor for an
ownership check), scoped to `event_type: :message` only — `:status_change`
events are never deletable, they're the order's audit trail. Update
whatever function renders a conversation's event list to account for
`status == :deleted`.

**UX judgment call, to confirm at implementation time:** unlike every other
entity in this plan, a chat message that's fully hidden can break the
reader's context (a reply pointing at nothing). Recommendation: render
deleted messages as a small "message deleted" placeholder in the thread
rather than omitting them entirely — content stays out of view, but the
conversational flow doesn't have silent gaps. This is a deliberate
exception to "fully invisible," worth confirming once it's rendered, not a
hard requirement of this plan.

**No new `/admin/conversations` screen** — this phase stops at
schema/context/query-filtering for both Conversation and its events.

**Commits:** 3 (Conversation schema+context+dev-delete gating; Conversation
query-filtering call-site updates; ConversationEvent schema+context+
rendering).

## Phase 6 — Extract the shared Multi+rescue+flag-cleanup hard-delete
helper

By this point there are three real, now-settled examples of the
Multi+rescue+polymorphic-flag-cleanup shape: `hard_delete_artist/1`,
`hard_delete_product/1`, `hard_delete_vendor_review/2` (and its
buyer/product siblings) — and Category/Conversation have confirmed they
*don't* need it (safe FK, dev-only gating respectively). Extract a shared
helper (e.g. `ArtsyNeighbor.Repo.HardDelete` or similar), parameterized by
the optional row-lock query, the `subject_type => ids` map to compute for
`Flag` cleanup, and the delete step itself. Bring `hard_delete_product/1`
up to the same row-locked standard as `hard_delete_artist/1` as part of
this commit. Pure refactor — existing tests should pass unchanged; this
doesn't resolve the deeper documented Flag-insert race, only the narrower
lock gap Product currently lacks.

**Commit:** 1.

## Phase 7 — User: schema-only

Add `status` (`:active | :suspended | :removed` — three states, since
"admin-suspended" and "self/admin-removed" are meaningfully different) +
`status_changed_at` + `status_changeset/2` to `Accounts.User` (currently has
none — see `lib/artsy_neighbor/accounts/user.ex`), following the Artist
shape. Add `Accounts.list_users_all_status/0` + `with_status/2`.

**Explicitly not in this phase:** no `soft_delete_user/1`/`hard_delete_user/1`
functions that touch orders/reviews/flags, no auth-pipeline enforcement (a
"removed" user can still log in until a follow-up wires that in). This is
deliberate — User is the only entity with no existing pattern to extend, it
touches auth, and it has 5–6 real FK/polymorphic landmines (`orders.buyer_id`,
`vendors_reviewed`/`buyers_reviewed`/`product_reviews.reviewer_id` all
`:restrict`/`:nothing`, `flags.reporter_id` `:restrict`, plus
`Flag.subject_type == "buyer"` also referencing `users`) that each need
their own product decision, not a mechanical port. FK/enforcement wiring is
a separate future plan.

**Commit:** 1.

## Verification (per phase, and at the end)

- `mix precommit` (compile --warnings-as-errors, format, full test suite)
  after every commit, not just at the end.
- For each entity gaining a status field: a manual smoke test that (a) a
  soft-deleted item disappears from its public list/browse view, (b)
  direct-URL access to its "show" page redirects/404s rather than
  rendering (this is exactly the bug Phase 0 fixes for Product — worth
  explicitly re-checking for Category/Conversation/Review too as each is
  added), (c) the admin all-status view still shows it, (d) restore brings
  it back to the expected status.
- For ConversationEvent specifically: verify a deleted message no longer
  shows its content to either party, that `:status_change` events remain
  undeletable, and that the chosen rendering (placeholder vs. omission)
  reads correctly in a live thread.
- Phase 0 and Phase 6 are pure-behavior-preserving refactors/fixes —
  verify via the existing test suite plus the one new regression test each
  adds (leak fix, row-lock).
- End of pass: full suite green, and a quick pass over `CLAUDE.md`'s
  "Schemas" section to add the new status fields/conventions now
  established (Category, Review, Conversation, ConversationEvent, User),
  matching how Artist/Product are already documented there, and to update
  its "Removal is usually soft" bullet to name the `soft_delete_*`/
  `hard_delete_*` convention explicitly.
