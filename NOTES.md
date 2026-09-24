# Notes / Backlog

A running, lightweight list of things to come back to — bugs, deferred
work, design decisions made but not yet built. Not a spec, not a plan doc
(see `docs/plans/` for those) — just a shared punch list so nothing gets
lost between sessions. Delete a bullet once it's actually done or no
longer relevant; no need to keep history here (git history covers that).

## Known bugs

- **Message compose box doesn't clear after sending**, in both Chrome and
  Firefox — noticed 2026-09-24 while reviewing the Conversation/
  ConversationEvent status-field work. Pre-existing, unrelated to that
  change. `ConversationLive.Show`'s `post_msg` handler resets `message_key`
  to force a fresh form (`lib/artsy_neighbor_web/live/conversation_live/show.ex`),
  which isn't actually clearing the input in the browser — worth a look at
  whether the `id={"new_msg-#{@message_key}"}` remount is actually firing,
  or whether the input's `phx-debounce` is fighting it.

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

1. **Admin moderation pass** — `/admin/flags` (review/resolve/dismiss
   reports), a public reviews display, "flag this review" entry points,
   and notifying a reporter when their flag's status changes.
   `CLAUDE.md`'s Known Issues bullet says these four need to ship
   together. **Design decision already made, not yet built:** `Flag` needs
   a new status (e.g. `:subject_removed`, not `:dismissed`/`:removed`) for
   when a flagged review is soft-deleted by its own author before any
   admin acts on the flag.
   This pass is also where the still-missing `/admin/conversations` screen
   (to actually call `Conversations.soft_delete_conversation/1`/
   `restore_conversation/1`) belongs.
2. **Email scaffolding** — buyer gets a completion link by email when the
   vendor schedules pick-up (Swoosh is already in the project).
3. **Payment options** — cash or Interac at the door; needs a
   `payment_method` field on orders.
4. **Payment scaffolding** — `Logger` stubs for `charge_buyer`,
   `charge_platform_fee`, `issue_refund` (Stripe drops in later).
5. **Styling pass** — deferred; do a dedicated design-mockup session
   before touching real code.
6. **Multi-item cart on `ArtistLive.Store`** — deferred.
7. **Delivery completion flow** — deferred, not planned for launch.
8. **Vendor/admin polish**: vendor dashboard preview-before-going-live;
   admin can already set all three artist statuses, vendor can only
   toggle active/inactive (by design).

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
- **Flag-cleanup delete paths have a narrow race + triplicated code** —
  `delete_product/1`, `delete_reviewed_with_flags/2`, `delete_artist/1`
  each delete matching `Flag` rows then the entity in one unlocked
  `Ecto.Multi`, so a `Flag` inserted in that instant can outlive the
  entity it references; the same Multi shape is hand-copied 3x.
- **FK cascade + remove_entity() rollout is still partial** — only Artist
  has real FK cascades; Product has its own soft-delete but its
  dependents (`product_reviews`, etc.) aren't cascaded yet.
- **Nullable bio/medium** on Artist — revisit when ready.
- **Unread badge implementation** — works, but has some complexity worth
  revisiting eventually. Do NOT refactor until explicitly asked.
- **Nav UI** — top strip cuts off on small screens; arrow visibility needs
  a JS scroll listener. Deferred until closer to deployment.
