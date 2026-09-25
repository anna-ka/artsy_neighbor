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

0. **Housekeeping** — `mix format`
   sweep in one mechanical commit (#20), trim the entity-removal
   docstrings (Tech debt), fix the compose-box bug (Known bugs).
1. **Design system + branding** — mockups → pick a direction → DaisyUI
   theme, layout/nav (incl. the small-screen nav issue), shared
   components, LocalPalette name (#14); restyle only the key public pages
   (home, artist page, store). Later pages get the new look as they are
   built or reworked. Consider a throwaway branch for trying directions.
2. **Private deployment (just the developer)** — Fly.io, Tigris for image
   storage (#17, #18), basic-auth password on the whole site. Done step
   by step with a written runbook in `docs/deploy.md`; finish by tearing
   the app down and rebuilding it from the runbook. Add a GitHub Actions
   workflow running `mix precommit` around this time. No continuous
   deployment — `fly deploy` stays manual.
3. **Buyer + vendor features** — artist-page collections and the empty
   "Uncategorized" fix (#13), purchase history (#11), vendor tools and
   product status (#16; leaning towards leaving visible-but-`:unavailable`
   products out of the first release), sales page with reviews/stats (#12).
4. **Admin support tools** — enough to quickly find, view, edit, restore,
   or soft-delete any user/artist/product/order/review (part of #1).
   Includes the restore-button no-op and the missing `/admin/reviews`.
   Full flag moderation is NOT in this step (see 7).
5. **Email + focused security check** — real outgoing mail (#2, #10);
   basic authorization checks (can a vendor touch another vendor's data,
   can a buyer see another buyer's orders, upload safety) — part of #21.
6. **Developer's own rehearsal** on the deployed site, as vendor, buyer,
   and admin; fix what turns up. Then **invite testers**.
7. **Before public launch** — full flag moderation pass (rest of #1),
   payments (#3, #4), anonymization (#9), thorough security audit incl. an
   experienced human reviewer (#21).

Test audit (#19) runs alongside, not as one block: in each pass, walk
through that area's tests (what they check, what's missing). A session
on how the test suite is organized is a good first step.

## Known bugs

- **Message compose box doesn't clear after sending**, in both Chrome and
  Firefox — noticed 2026-09-24 while reviewing the Conversation/
  ConversationEvent status-field work. Pre-existing, unrelated to that
  change. `ConversationLive.Show`'s `post_msg` handler resets `message_key`
  to force a fresh form (`lib/artsy_neighbor_web/live/conversation_live/show.ex`),
  which isn't actually clearing the input in the browser — worth a look at
  whether the `id={"new_msg-#{@message_key}"}` remount is actually firing,
  or whether the input's `phx-debounce` is fighting it.

## Known limitations / deliberately deferred

Things that are knowingly incomplete by design (not bugs), and that anyone
working on the code should keep in mind.

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

## Deferred follow-ups (small, scoped)

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

## Features / next chunks of work

1. **Admin moderation pass** . The admin UI right now is a rough draft. It is incomplete and inconvenient for any even a small volume of users. Need to add good comfortable UI to moderate vendors, users and buyers, reviews, products and to resolve flags. Not sure if UI for moderating converstions is needed. Also not sure what it may look like.

 `/admin/flags` (review/resolve/dismiss
   reports), a public reviews display, "flag this review" entry points,
   and notifying a reporter when their flag's status changes.
   The "Flagging" bullet under Known limitations above says these four
   need to ship together. **Design decision already made, not yet built:** `Flag` needs
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

  14. The name of the website in the end will be LocalPalette, not ArtsyNeighbor. We need to adjust UI for that. Code can remain as is (we do not need to rename the project)

  16. Do a pass on Vendor dashboard and tools. Editing products from Vendor dashboard is very rough. We want to be allow vendors to set status of products to :archived. They should be able to see them in their list of products clearly labelled as Archived so they can restore them with minimal changes. I am also contenplating allowing them to have :unavailable products - those they are working to make more of, sort of sold out products. These would show on their stores but could not be purchased until status changes. Not sure if this later should be included in the first release.

  17. I need some solid advice and to make decisions about how to store images. Right now everything is local on my laptop, I have no idea how to set it up so it would work on server.

  18. I am contemplating a "testing" hosting on on Fly.io or similar service. I want it to be unaailable to public for now, only to a few selected testers. And also as a way to even see what is involved in setting it up on a server. 

  19. Audit of tests: for now they are all written by Claude, most decisions are made by Claude and I only skim them. This is one of my weaker points as I have never done true deployment. But I do want good informative test covereage. So I suppose an audit of existing tests and probably extending them.

  20. Get rid of formatting debt.

  21. A very serious and thorough security audit. I am thinking of running Claude Fable on it and later (or earlier) also askign an experienced human developper for suggestions. I have no experience in this area.






## Tech debt

- **`mix format` debt scattered across the codebase** — confirmed files
  so far: early LiveView templates written while learning Phoenix
  (200+ line diffs each), plus several more discovered mid-pass
  (`custom_components.ex`, `conversations.ex`, `conversation.ex`,
  `conversation_event.ex`, `conversation_live/index.ex`, and others).
  **Lesson learned the hard way, twice: never run `mix format` on a file
  without first checking `mix format --check-formatted <file>` — it's easy
  to accidentally blast a 200+ line unrelated reformat onto a file with
  real, wanted changes buried in it.**
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
- **Entity-removal-consistency pass docstrings/comments need a trim once
  done** — agreed 2026-09-21, to happen only after Phase 7 (the plan's
  last phase) is committed: the pass-specific narrative accumulated in
  code comments (e.g. "round 1 of /code-review found X") was useful while
  the pass was in flight but should collapse back to durable "what + the
  one non-obvious why" once it settles — the blow-by-blow belongs in git
  history, not living forever in a docstring.
- **Nullable bio/medium** on Artist — revisit when ready.
- **Unread badge implementation** — works, but has some complexity worth
  revisiting eventually. Do NOT refactor until explicitly asked.
- **Nav UI** — top strip cuts off on small screens; arrow visibility needs
  a JS scroll listener. Deferred until closer to deployment.
