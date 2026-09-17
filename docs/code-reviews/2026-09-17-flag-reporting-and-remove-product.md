# Code review — flag reporting, `remove_product/1`, review-flag consistency

**Status as of 2026-09-17:** findings 1 and 3 fixed. Findings 2 and 4 deferred
together as one future pass — see "Deferred" note at the end.

**Reviewed:** 2026-09-17, via `/code-review` (fresh-context subagent review)
**Scope:** the full uncommitted working tree at review time — three pieces of
work done across two sessions without an intermediate commit: (a) the
flag-reporting feature (`FlagLive.New`, `Reviews.create_flag/1` UI, entry
points), (b) `Products.remove_product/1` (soft archive, added mid-review of
(a)), and (c) `Reviews.resolve_subject/2` consistency across all 6 `Flag`
subject types plus fixing the review-delete flag-orphaning gap (also added
mid-review of (a)). Full suite was 552/552 at review time.

## Fixed

1. **Misleading archive confirm dialogs.** Both `AdminProductLive.Index`'s
   and `VendorLive.Dashboard`'s "archive" confirm text promised the action
   "can be reversed by editing its status" — but neither
   `AdminProductLive.Form` nor `VendorLive.ProductForm` exposes a `status`
   field (unlike `AdminArtistLive.Form`, which does). There is currently no
   in-app way to un-archive a product.

   **Resolution:** corrected both confirm dialogs to describe reality — the
   archive is reversible in principle (the row and its data are kept), but
   not self-service yet. Building an actual restore UI is separate scope,
   not done here.

2. **Dead error-handling branch — crash on constraint violation.**
   `Products.delete_product/1` and the new
   `Reviews.delete_reviewed_with_flags/2` (backing `delete_vendor_review/2`,
   `delete_buyer_review/2`, `delete_product_review/2`) each wrap a
   delete-then-cleanup-flags step in an `Ecto.Multi`, but the
   `{:error, _failed_step, reason, _} -> {:error, reason}` case clause could
   never actually fire: `Repo.delete/1` on a plain struct raises
   `Ecto.ConstraintError` on a real constraint violation (e.g.
   `product_reviews.product_id`'s `on_delete: :restrict`, with no
   `foreign_key_constraint` declared on `Product.changeset/2`) rather than
   returning an error tuple. This duplicated a bug already found and logged
   (`project_delete_product_review_crash` in project memory) — the review
   showed it had spread to a second location, `reviews.ex`, along the way.
   Separately, `AdminProductLive.Index`'s `"delete"` handler still did a bare
   `{:ok, _} = Products.delete_product(product)` match, so even a clean
   `{:error, _}` tuple would still crash the LiveView via `MatchError`.

   **Resolution:** added `rescue error in [Ecto.ConstraintError, Postgrex.Error] -> {:error, {:constraint_error, Exception.message(error)}}`
   to both functions, matching the pattern `Artists.delete_artist/1` already
   uses (from the 2026-09-16 review). Updated `AdminProductLive.Index`'s
   `"delete"` handler to `case` on the result with an error flash, same as
   `AdminArtistLive.Index`. The three review-delete call sites
   (`order_live/detail.ex`, `vendor_live/orders_show.ex`) already handled
   `{:error, _}` generically — no change needed there.

## Deferred together (one future pass)

3. **Narrow flag-orphaning race.** None of the three
   delete-then-cleanup-flags functions (`Products.delete_product/1`,
   `Reviews.delete_reviewed_with_flags/2`, `Artists.delete_artist/1`) lock
   the row being deleted. A `Flag` inserted in the instant between the
   `delete_all` and the final delete can survive, orphaned, referencing a
   now-deleted product/review/artist. Note: `delete_artist/1`'s existing
   `FOR UPDATE` lock does **not** actually close this gap either — it only
   blocks inserts of real-FK'd rows (orders/reviews/conversations); `Flag`
   has no FK at all, so nothing currently blocks a concurrent flag insert
   during any of these three deletes. `products.ex`'s docstring previously
   claimed this class of locking was unnecessary for a single product — that
   reasoning was wrong and has been corrected, though the lock itself isn't
   added yet.
4. **Triplicated `Ecto.Multi` shape.** The same "delete matching `Flag` rows,
   then delete the row" pattern is now hand-copied three times (products.ex,
   reviews.ex, artists.ex). A shared helper (e.g.
   `Reviews.delete_with_flag_cleanup/2`) would remove the duplication and
   guarantee any future fix — including item 3 above — lands everywhere at
   once.

   **Why deferred together:** fixing the race properly likely means adding
   the lock inside the shared helper from item 4, so fixing them separately
   would mean writing the lock three times only to delete two of them right
   after. Logged in project memory
   (`project_delete_product_review_crash.md`) for a dedicated future pass.

## Also checked, not a finding

- Confirmed `mix format --check-formatted` reports only pre-existing debt
  (well over 80 files across the repo, unrelated to this diff — see
  `project_mix_format_debt.md`) — none of the files actually authored or
  edited this session are unformatted.
- Confirmed `mix compile --warnings-as-errors` already fails identically on
  a clean checkout of `main` (scaffold-generated `product_image_live`/
  `product_option_live` files with dead routes) — pre-existing, unrelated to
  this diff.
- Full suite re-run after both fixes: 552/552, no regressions.
