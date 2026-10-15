# From mockups to the real theme and components

Status: plan, agreed in outline 2026-10-15; not started.

Follows `docs/plans/2026-09-28-design-system.md`, where the look was
decided in static mockups. This step moves those decisions into the
app. For where each part of the styling lives, and how a change
travels from the theme to every page, see
**`docs/design/how-styling-works.md`**.

## Principles

- **The mockups stay** in `docs/design/mockups/`, as the place to try
  out and fine-tune looks. A change is tried there first and then
  copied into the app. The mockups and the app use **the same names**
  for colours and settings, so copying is usually one line.
- **One theme, light only.** Dark mode is left out for now: the site
  was never designed for it, and a dark theme for art is its own
  design job.
- **Looks before features.** Each page is first restyled with the data
  it already has. New features shown in the mockups (motto, featured
  works, tabs merging the store into the artist page, commissions
  setting, returns policy) come afterwards as their own commits. The
  site works after every step.
- **Missing features appear as placeholders.** Where a mockup shows
  something not built yet (a "Commissions" tab, a "Follow" button, a
  motto), the restyled page includes it as a placeholder, so the page
  is judged with its final layout. Rules:
  - Every placeholder uses the shared `<.placeholder>` component, so one
    search finds them all.
  - It looks exactly like the real thing. Pressing it shows a short
    "Not built yet" message rather than doing nothing (a button that
    does nothing looks broken).
  - Each one is listed in **`docs/design/placeholders.md`**, with what
    it needs to become real. The entry is deleted when it is built.
  - **Before testers see the site, every placeholder is either built or
    removed** (part of the rehearsal step in `NOTES.md`'s order of
    work).
- **Tests keep passing.** `mix precommit` (compile with warnings as
  errors, format, full test suite) runs before every commit, not after
  every small change. Restyling will break some tests that find
  elements by their old structure or classes; updating those is part
  of the same commit. A test that checks what a page *says or does*
  should pass unchanged: if one fails, that is a real problem, not a
  test to adjust.

## Phase 0: what the mockups haven't decided yet

These are everyday elements that every page needs, and they have
theme colours of their own, so they are decided **before** the theme is
written. One new mockup sheet, `docs/design/mockups/elements.html` (like
`wordmark.html`), shows them side by side with a few versions each.
Should be short.

1. **Links:** colour normally, on hover, on keyboard focus, and
   whether visited links look different (helpful for orientation, but
   uncommon on shops). Underlined always, or only on hover? (For our
   audience: probably always, so links are recognisable without
   hovering.) Also the quiet links already in the mockups ("Report a
   concern", "Back to top") as a second, deliberately quieter style.
2. **Buttons:** main (`primary`), ordinary/secondary (outline), quiet
   text button, **danger** (Delete, Remove; a calm but clear red,
   probably outlined rather than solid so it doesn't shout), disabled,
   and "working…" (while saving). Also: what a **confirmation** before a
   dangerous action looks like (today: the browser's plain pop-up).
3. **Messages ("flash"):** today they float in the top-right corner and
   are easy to miss (see `how-styling-works.md`, section 8). Versions
   to compare:
   - a wide banner at the top of the content, under the header, in
     larger text, staying until closed;
   - the same, but fixed to the top of the screen, so it is seen even
     when the page is scrolled down;
   - for forms: the message right next to the button that was pressed.

   Colours for success, information, warning and error: calm and warm
   rather than bright, always with an icon and words, never colour
   alone. Decide whether success messages fade away on their own
   (errors never should).

   **The mockup decides only the look** (colours, size, icon, close
   button) and gives a first impression of placement. Placement and
   behaviour are decided in the real app, because only there can we
   see: messages that arrive after moving to another page (e.g.
   "Product saved" on the product list), messages after an action far
   down a long page, two messages at once, Phoenix's "We can't find
   the internet" message, and whether screen readers announce them.
   For that, the style guide page (Phase B) gets buttons that trigger
   real messages, and then two or three real flows are checked
   (saving a product, a failed login, sending a message).
4. **Form fields** (also not mocked up yet, and on every vendor page):
   text box, dropdown, checkbox, the field label, help text, and how
   an error under a field looks.

## Phase A: theme and fonts

In `assets/css/app.css`:

- Replace the four stock themes (`light`, `dark`, `dark-old`,
  `light-old`) with one theme, **`localpalette`**, from the mockup's
  Gallery values plus the Phase 0 decisions.
- Add our extra settings: muted text colour, soft panel colour, fonts,
  section gap, content width.
- Remove the theme switcher script from `root.html.heex` (it was there
  for dark mode).
- Remove the old `artsy-teal` / `artsy-bg` colours once nothing uses
  them.
- Fonts: Sentient (titles), Switzer (everything else), Spline Sans
  Mono (one small label), Fraunces (wordmark).
  **Where the font files come from (decided 2026-10-15):**
  - Sentient and Switzer are under the ITF Free Font License 2.0
    (`License/FFL.txt` next to each font in
    `docs/design/mockups/fonts/`, gitignored). Free for commercial
    use, nothing to buy; self-hosting allowed; but the files may not
    be passed on, and "repository" is named as a forbidden way (the
    repo is private, but we don't rely on that). The files must also
    not be changed (no converting or subsetting).
  - **Now:** load them from Fontshare's own font service (the
    "Fontshare API"), one line of CSS, no files. The licence allows it
    but promises nothing about availability; if it is down, the
    backup fonts in the font list show instead.
  - **Later:** download the official files from Fontshare during the
    deploy build, so we host them ourselves without them being in git.
  - **Later:** pick a couple of decent open-licence fonts as backups
    that look closer to Sentient and Switzer than Georgia and the
    system font do, for the rare case the service fails.
  - Fraunces and Spline Sans Mono are under the open font licence
    (OFL), so they can be hosted by us, in the repo.
  - Anyone running the site in another city downloads Sentient and
    Switzer from Fontshare themselves (the licence requires it); goes
    into the setup instructions.

Pages will look different after this step (new colours and fonts) even
before anything else changes. Some pages may look odd until restyled.

## Phase B: style guide page

`/dev/styleguide`, only in development (like `/dev/mailbox`): every
colour, text size, font, and component on one page. A theme change is
judged here at a glance before looking at real pages. Grows with each
component in Phase C. Includes buttons that trigger real flash
messages, for deciding their placement (see Phase 0, item 3).

## Phase C: shared components

Built once, in `core_components.ex` (Phoenix's basics, adapted) and
`custom_components.ex` (ours). Mostly direct translations of classes in
`mockup.css`:

- `core_components.ex`: `<.button>` (main / ordinary / quiet / danger),
  `<.input>` (form fields and their errors), `<.flash>` and
  `<.flash_group>` (the new message style).
- `custom_components.ex`: artwork tile (option to hide the price),
  collection/category tile, chip, star rating, review, section heading
  with a "See all ›" link, "Show more" text button, quiet link, report
  link, and `<.placeholder>` (see Principles).
- The existing `button_artsy`, `product_card`, `category_card` are
  replaced by these and removed once unused.

## Phase D: the page frame

In `layouts.ex` / `root.html.heex`: header (logo, wordmark, search,
links), category bar, water background (header and sides), footer, and
where messages appear. The logo waits for the final version from the
developer's daughter; the current draft is used until then.

## Phase E: pages, one at a time

Artist page → product page → home, then the remaining public pages,
then vendor and admin pages (these mostly need Phase 0's buttons,
forms and messages, less of the gallery look). Each page: restyle with
existing data, screenshots at computer and phone width, the
developer's review, commit. Fixed colours left in each file (about
100 in 10 files) are replaced with theme names as it is restyled.

Feature work found along the way goes into `NOTES.md`, not into the
restyling commits.
