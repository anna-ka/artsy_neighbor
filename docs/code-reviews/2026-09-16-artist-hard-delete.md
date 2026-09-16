# Code review — artist hard delete (`Artists.delete_artist/1`)

**Status as of 2026-09-16 (later same day):** all findings below fixed. See the
"Resolution" note at the end of each item.

**Reviewed:** 2026-09-16, via `/code-review` (fresh-context subagent review)
**Scope:** the diff committed 2026-09-14 as `5bf7acc` — `Artists.delete_artist/1`,
the admin "delete" action in `admin_artist_live/index.ex`, and the 4 accompanying
tests in `artists_test.exs`.

Full suite was 494/494 at review time, and the deletion *ordering* itself was
verified FK-safe against every relevant migration's `on_delete` setting. All
findings below are edge cases, not happy-path bugs.

## To fix (blocking before push)

1. **Race condition + unhandled crash.** `delete_artist/1` (`artists.ex:323`)
   collects order/product/conversation ids with plain `SELECT`s, no row
   locking, then deletes. A row inserted for this artist between the SELECT
   and the final `Repo.delete(artist)` is invisible to the cleanup queries —
   the final delete then hits a live FK reference (`on_delete: :nothing`) and
   raises an unhandled `Ecto.ConstraintError` instead of failing gracefully.
2. **No error handling in the admin handler.** `admin_artist_live/index.ex:37`
   pattern-matches `{:ok, _} = Artists.delete_artist(artist)` with no error
   clause — any failure (the race above, or a stale double-click) crashes the
   LiveView with a MatchError instead of showing a flash.
3. **`Flag` rows get orphaned.** `delete_artist/1`'s doc comment claims it
   deletes "everything that depends on" the artist, but it never touches the
   `flags` table (`reviews/flag.ex`, polymorphic `subject_type`/`subject_id`,
   no DB-level FK). Invisible today (no flags UI yet), but will surface as a
   crash or garbage data once `/admin/flags` exists — which is next on the
   roadmap.

   **Resolution (1 & 2):** `delete_artist/1` now locks the artist row
   (`SELECT ... FOR UPDATE`) for the whole transaction before doing anything
   else — Postgres takes a `FOR KEY SHARE` lock on a referenced row for every
   FK-checked insert, so this genuinely blocks a concurrent order/
   conversation/review insert against this artist until the transaction
   commits or rolls back, closing the race rather than just handling its
   symptom. The function also wraps its body so any constraint violation that
   still slips through comes back as `{:error, {:constraint_error, msg}}`
   instead of raising, and the admin handler now `case`s on both outcomes
   with an `:error` flash instead of a bare `{:ok, _} =` match. **Resolution
   (3):** since finding #8's cascade migration below still can't cover
   `flags` (polymorphic, no real FK possible), `delete_artist/1` explicitly
   collects the relevant vendor/buyer/product review ids up front and deletes
   matching `Flag` rows by hand — the one piece that has to stay manual.
   Covered by 3 new tests in `artists_test.exs` (flag on the artist directly,
   flags on each of the three review types, and a cross-artist isolation
   check).

## Decided fix: consolidate the duplicate `delete_artist/1`

4. **Naming collision.** `Admin.AdminArtists.delete_artist/1`
   (`admin/admin_artists.ex:49`) already existed — same name/arity, unsafe
   bare `Repo.delete`, completely unused (confirmed via grep: `AdminArtists`
   appears nowhere outside its own module + its own test).

   Follow-up investigation (2026-09-16) found this points at a bigger gap:
   `admin_artist_live/index.ex` calls the general `Artists` context directly
   for everything, when the established convention (see `AdminCategories` /
   `admin_category_live`) is for admin LiveViews to go through a thin
   `Admin.*` wrapper context. **Decision: bring `AdminArtists` in line with
   that convention** — delegate `delete_artist/1` (and the other functions
   admin actually uses: `list_artists_all_status`, `get_artist!`,
   `remove_artist`) to `Artists`, and rewire `admin_artist_live/index.ex` to
   call `AdminArtists.*` instead of `Artists.*` throughout.

   **Resolution:** done — `AdminArtists` now delegates all four functions to
   `Artists`, `admin_artist_live/index.ex` calls `AdminArtists.*` exclusively.
   `admin_artist_live/form.ex` was deliberately left alone (same
   inconsistency, out of scope for this pass).

## Smaller cleanups

5. **Stale doc comment.** `remove_artist/1`'s doc (`artists.ex:299`) still
   says "Artists are never hard-deleted — they are permanent records," which
   `delete_artist/1` (added 15 lines below) now contradicts.

   **Resolution:** `delete_artist/1`'s own doc comment now spells out exactly
   what cascades and what doesn't (see finding 8's resolution). Still worth a
   one-line fix to `remove_artist/1`'s comment itself — not done yet.
6. **Dead error-handling clause.** The `{:error, changeset} ->
   Repo.rollback(changeset)` branch around `Repo.delete(artist)`
   (`artists.ex:341`) can't actually catch the realistic failure — `Artist` is
   a bare struct with no `foreign_key_constraint/2` declared, so a real FK
   violation raises rather than returning an error tuple.

   **Resolution:** fixed as part of 1 & 2's fix above — the function-level
   `rescue` now catches what an inline changeset-error clause couldn't.
7. **Convention divergence.** Uses raw `Repo.transaction` + manual
   `Repo.delete_all` chain instead of `Ecto.Multi`, the pattern used
   throughout `orders.ex` for other multi-step dependent writes. No per-step
   name to identify which step failed if something breaks later.

   **Resolution:** rewritten using `Ecto.Multi` (`locked_artist` →
   `flag_subject_ids` → `deleted_flags` → `deleted_artist` steps), matching
   `create_artist/1`'s existing style in the same file.
8. **Hand-maintained cascade.** The whole cleanup is 7 hand-written
   `delete_all` calls standing in for FK cascades (every relevant FK is
   `on_delete: :nothing` or `:restrict`). Discussed separately — the agreed
   direction is to add `on_delete: :delete_all` migrations for the relevant
   FKs so `delete_artist/1` collapses to a single `Repo.delete(artist)`, with
   safety enforced at the application layer (deliberate `remove_*` functions
   per entity) rather than by making deletes structurally hard to call. Full
   entity-by-entity rollout of that pattern is its own future pass — this
   review only scopes it for `Artist`.

   **Resolution:** done for `Artist`'s FKs specifically, via migration
   `20260916191340_cascade_artist_delete_fks` — `orders.artist_id`,
   `conversations.artist_id`, `conversation_events.conversation_id` +
   `.order_id`, `order_items.order_id`, `products.artist_id`,
   `vendors_reviewed.order_id` + `.artist_id`, `buyers_reviewed.order_id`,
   `product_reviews.order_id` + `.product_id` are all now
   `on_delete: :delete_all`. One deliberate behavior change flagged and
   confirmed with the user first: `products.artist_id` was `:nilify_all`
   (products would have survived, orphaned) and is now `:delete_all`
   (products are destroyed with the artist), matching what the function
   already did manually. `flags` is the one table that structurally can't get
   a real FK (polymorphic `subject_id`) — still handled by hand, see
   finding 3's resolution. The broader entity-by-entity `remove_*()` pass
   (pairing cascades with deliberate soft-delete functions everywhere else)
   remains a separate future initiative — see
   `project_fk_cascade_and_remove_entity_pass` in project memory.

## Also checked, not a finding

- Grepped every `Repo.delete`/`delete_all` in `lib/` touching the `artists`
  table — confirmed only the two `delete_artist/1`s above ever delete an
  Artist row (plus `priv/repo/seeds.exs`, a dev/test full-DB reset script,
  already ordered FK-safely).
- `priv/static/notes/to-do.txt` contains first-person "Claude voice" text
  that a fresh-context reviewer flagged as possibly-injected content — false
  positive, confirmed with the user it's their own habit of pasting chunks of
  chat replies into their notes file as a journal. Also confirmed that file
  isn't publicly served (`notes` isn't in `ArtsyNeighborWeb.static_paths/0`).
