# From mockups to the real theme and components

Status: plan agreed 2026-10-15. Phase 0 done (decisions below);
Phase A done 2026-10-15 (notes at its end); Phase B's page built
2026-10-15 (notes at its end); Phase C under way (button, input and
messages done 2026-10-15, confirm dialog, cards, small text pieces,
star rating and review 2026-10-16; notes at its
end).

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

### Phase 0 decisions

Sheet: `docs/design/mockups/elements.html`.

- **Links (2026-10-15): version 3**, the calmest. The ordinary text
  colour (`base-content`) with a thin 1px seal-slate (`secondary`)
  underline set 4px below the text (clear of g and y); on mouse-over
  the text turns slate and the line becomes 2px. Links are recognised
  by the underline, not the colour. Visited links look the same as
  unvisited ones. Quiet links ("Report a concern", "Back to top"):
  muted grey, underlined, 14px, ordinary text colour on mouse-over.
  Keyboard focus: a 2px slate ring with a little space around the
  text. Quiet buttons and "Show more" links follow the same style.
  Applied to `mockup.css`. Not chosen: the browser's standard
  underline (1), slate links with a soft underline (2, briefly chosen
  by mistake), no underline until hover (4, colour alone and
  hover-dependent), a different colour for visited links (5).
- **Buttons (2026-10-15): family 1, "Dark".** Four kinds:
  - **main** (one per area): near-black fill (`primary`), slightly
    lighter on mouse-over;
  - **ordinary**: outlined in the text colour, soft cream fill on
    mouse-over;
  - **quiet**: looks like a link (same style as links);
  - **danger** ("Delete this work"): outlined in a calm brick red
    (`--color-error`, `#A63A2E`, about 6:1 contrast), faint red fill
    on mouse-over. Never solid red, except the final "Yes, delete".

  All: 44px tall, 10px corners, 1.5px outlines, Switzer Regular.
  Keyboard focus uses the same slate ring as links. "Not available"
  is a readable grey (not see-through). "Working" shows a small
  turning circle and changes the words ("Saving…", "Deleting…").
  Applied to `mockup.css` (`.btn-primary`, `.btn-outline`,
  `.btn-quiet`, `.btn-danger`, `.btn-danger-final`). Not chosen: slate
  buttons (2), softly filled buttons without outlines (3, less
  obviously buttons).
- **Confirming a delete (2026-10-15): A, a box in the middle of the
  screen over a dimmed page.** A heading naming the thing ("Delete
  “Crow at Ross Bay”?"), one or two sentences on what happens (and
  that it can be restored, when it can), then "No, keep it"
  (ordinary) and "Yes, delete" (solid red). Replaces the browser's own
  "localhost says / OK / Cancel" pop-up. One shared component for
  every delete and remove action. Not chosen: B, the question
  appearing in place of the button (pushes lists around).
- **Messages (2026-10-15): look 1, "Tinted".** A pale wash of the
  kind's colour (9%) with a thin outline in it (1.5px), 12px corners,
  16px text. Four kinds, each with its own colour and icon (colour is
  never the only clue): success (moss green `#3D6B4F`, tick),
  information (seal slate `#4C5075`, "i"), warning (ochre `#8A5A0F`,
  triangle), error (brick red `#A63A2E`, "!"). These become the
  theme's `success` / `info` / `warning` / `error` colours. Every
  message starts with a few bold words saying what happened, then
  what to do, and has "Close" in words. **Nothing fades by itself**
  (a message that disappears while being read frustrates older
  users); messages also go when moving to another page. Note: Phoenix
  only has `:info` and `:error` messages by default; success and
  warning are added as two more kinds.
  **Placement, first impression: stays on screen at the top** (fixed
  to the top of the window, so it is seen even when scrolled down).
  In the mockup, the other two places (under the header; next to the
  button) were easy to miss: it took the developer a while to find
  the message, which is the problem we're solving. To be confirmed
  in the real app (Phase B). Not chosen: side bar (2, easiest to
  overlook), solid (3, shouts).
- **Form fields (2026-10-15): version 1, "Outlined".** White boxes with
  a clear grey edge (`--field-edge`, `#8C857B`, about 3.6:1 against the
  page; the divider line colour is too faint for fields), 1.5px, 10px
  corners, 44px tall. While typing: slate edge and a soft slate glow.
  A mistake: red edge and a sentence under the field, with an icon,
  saying how to fix it. Not available: readable grey. Also, in every
  version:
  - the label always above the field (never only grey text inside it);
  - help text between the label and the field, read before typing
    (the app's `<.input>` has no help text today; to be added);
  - "(optional)" in words, instead of * on required fields;
  - 16px text inside fields (smaller makes iPhones zoom in);
  - checkboxes 22px (today's are small), near-black when ticked,
    the whole line clickable;
  - dropdowns with a simple, larger arrow.

  - example text inside an empty field ("For example
    instagram.com/marenholt") in a fainter grey (`--field-edge`,
    `#8C857B`): in the muted text grey it looked already filled in.
    Use it only for examples, never for anything people must read.

  Not chosen: filled
  cream boxes (2, blend in), underline only (3, not recognised as a
  place to type).

**Phase 0 done (2026-10-15).**

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

### Phase A done (2026-10-15)

- `localpalette` uses the mockup's hex values directly (not daisyUI's
  usual `oklch(...)`), so copying from `mockup.css` stays one line.
  `accent` (unused by our design) is the same slate as `secondary`;
  `neutral` is the text colour. Flat look (`--depth: 0`).
- Extra colours `muted`, `soft`, `field-edge` and fonts `heading`,
  `label`, `wordmark` are in `@theme static`, so Tailwind classes such
  as `text-muted` and `font-heading` exist; "static" keeps them in the
  built CSS before any page uses them. Section gap, content width and
  heading weight are plain settings in `:root`, with the mockup's phone
  values below 760px.
- Switzer is the default font for everything (`--font-sans`); `h1`–`h3`
  get Sentient Light, unless a class on the title says otherwise.
- **Text size not changed** (still the browser's 16px; the mockups use
  15px). To be decided on the style guide page (Phase B), with our
  audience in mind.
- Fontshare link in `root.html.heex`: Sentient 300/400 (with italics),
  500, 700; Switzer 400–700. Fontshare quietly swaps in a different font
  for some weight lists; the comment there says to check the result.
- Fraunces (variable, with the SOFT and WONK settings the wordmark needs;
  official file from Google's font repository) and Spline Sans Mono
  Regular are in `priv/static/fonts/`, each with its `OFL.txt`.
- Removed: the four stock themes, the theme switcher script, the
  sun/moon `theme_toggle` component (only on Phoenix's leftover pages),
  the custom `dark:` setting (no page used `dark:` classes), and
  `artsy-teal` / `artsy-bg` (their three uses now point at theme colours;
  those components are replaced in Phase C anyway).

## Phase B: style guide page

`/dev/styleguide`, only in development (like `/dev/mailbox`): every
colour, text size, font, and component on one page. A theme change is
judged here at a glance before looking at real pages. Grows with each
component in Phase C. Includes buttons that trigger real flash
messages, for deciding their placement (see Phase 0, item 3).

### Phase B so far (2026-10-15)

- The page is `lib/artsy_neighbor_web/live/dev_live/styleguide.ex`,
  routed in the router's `:dev_routes` block with the public pages'
  `on_mount` hooks, so it shows inside the real page frame.
- **Body text: 16px**, the browser's own default. Not set in
  `app.css` on purpose: setting it would override visitors who have
  made their browser's text larger. 17px and 18px were compared; 18px
  looked too large-print for the site, 15px (the mockups) too small for
  our audience.
- Message buttons (information, error, two at once, after moving to
  the home page) sit at the top and bottom of the page. First finding,
  with today's messages: **two messages at once lie on top of each
  other**, so only the second is seen. The new `<.flash_group>` in
  Phase C must stack them (done). Placement and look are decided in
  Phase D, with the trial switches added in Phase C (see there).

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

### Phase C so far (2026-10-15)

- **Our own class names, not daisyUI's** (decided 2026-10-15): the new
  rules in `app.css` (`@layer components`) are `btn-base` + `btn-main` /
  `btn-ordinary` / `btn-quiet` / `btn-danger` / `btn-danger-final`;
  `field`, `field-label`, `field-help`, `field-input`, `field-error`,
  `field-check`; `msg` + `msg-success` / `-info` / `-warning` /
  `-error`. Only pages using `<.button>`, `<.input>` and messages
  changed; old `button_artsy` buttons and hand-written `btn btn-...`
  classes keep daisyUI's look until each page is restyled (Phase E).
  Not chosen: rewriting daisyUI's own `btn` / `input` rules (every
  button at once, but half old, half new looks and unclear which rule
  wins). The mockup's `.btn-primary` / `.btn-outline` are our
  `btn-main` / `btn-ordinary` (noted in `app.css`).
- **`<.button variant="...">`**: `main`, `ordinary` (default), `quiet`,
  `danger`, `danger_final`. `class` now adds to the kind's classes
  (before, it replaced them). Working: LiveView's
  `phx-click-loading` / `phx-submit-loading` show the turning circle,
  `phx-disable-with` changes the words; a working button keeps its
  colours (not the "Not available" grey), as in the mockup.
- **`<.input>`**: new `help` (between label and box) and `optional`
  ("(optional)" after the label). `class` adds to the box's classes;
  `error_class` removed (unused). Forms that still put a red `*` in
  their labels (product, profile, admin forms) switch to `optional`
  when restyled in Phase E.
- **Messages**: `:success` and `:warning` added. "Close" in words; only
  that button closes a message (before, a click anywhere on it did).
  `flash_group` (in `layouts.ex`) is fixed to the top of the window,
  centred, up to 36rem wide, messages stacked: **two at once no longer
  lie on top of each other.** The lost-connection messages were
  reworded ("We can't find the internet. Trying to reconnect…").
  Existing `put_flash(:info, ...)` calls that are really successes
  ("Saved") are switched to `:success`, with a few bold words first,
  page by page in Phase E.
- Style guide shows all of the above, with a "working" demo (the server
  waits two seconds).
- **Message trial (2026-10-16).** Trying the new messages in the app,
  the developer found solid messages far more noticeable, though
  jarring. Current leaning, after trying the switches below: **success
  and information tinted; warnings and errors solid; all messages
  "higher up", a quarter of the way down the window.** All messages
  form one column (`msg-column` in `flash_group`), so they never cover
  each other: warnings and errors first (seen first), then success and
  information. More than one message at once (especially a success and
  an error) is itself a sign of a confusing page, so it should be rare;
  it only has to stay readable, not look polished.
  The style guide has dev-only switches: look of warnings and errors
  (tinted / solid) and place of all messages (top / higher up /
  centre). The choice is remembered in the browser and applies on every
  page of the app (script in `root.html.heex`, rules in `app.css`);
  without it, and always in production, everything is tinted at the
  top, which is temporary. **Decided in Phase D**; then the chosen
  look and place become the only ones, and the switches, the script and
  the unused rules are removed.
- **Confirm dialog (2026-10-16).** One box for the whole app
  (`<dialog id="confirm-dialog">` in `root.html.heex`, outside the
  LiveView), opened by a short script in `assets/js/app.js` for any click
  on something with `data-confirm`. So every existing `data-confirm`
  (10 places) got the new box at once, and the browser's "OK / Cancel"
  pop-up is gone. The script takes over phoenix_html's own
  `phoenix.link.click` step, which Phoenix documents as the way to
  replace that pop-up. Attributes: `data-confirm` (the question, shown as
  the heading), `data-confirm-detail` (optional sentences),
  `data-confirm-yes` (default "Yes, delete"), `data-confirm-kind="ordinary"`
  (the yes button is then the main dark one, e.g. for restoring). "No,
  keep it" comes first and has the keyboard; Esc closes. The question
  is in Switzer, 17px, normal weight (the title font at 22px looked far too
  big next to the admin pages). The browser's
  own `<dialog>` gives the dimmed page, keeps focus inside and is
  announced by screen readers. Not chosen: a server-side dialog per
  button (much more markup, a round trip just to open a box).
  Wording fixed now only where "Yes, delete" would be wrong (archive a
  listing, cancel an order, the admin restore / archive / mark removed
  buttons); the other questions get a heading + detail split when their
  page is restyled in Phase E. Style guide: "Confirming" section.
- **The `custom_components.ex` list, in four steps** (agreed
  2026-10-16), each with its own style-guide section and commit: (1)
  cards; (2) small text pieces: chip, section heading with "See all ›",
  "Show more", quiet link, report link; (3) star rating and review; (4)
  `<.placeholder>` and `docs/design/placeholders.md`.
- **Cards (2026-10-16).** Named "cards" by the developer (the plan said
  "tiles"). `<.artwork_card product={...}>`: first photo cropped to 4:3
  in a thin outline, title in bold Switzer, a details line ("Artist ·
  materials, size", leaving out what's missing; sizes never break across
  lines), the price. `show_price={false}` for the home page,
  `show_artist={false}` for the artist's own page, `show_size={false}`
  to leave the size out, and `location="..."` to add the artist's
  neighbourhood (text, not an on/off switch: artists have no
  neighbourhood field yet). Prices: whole dollars only, rounded to the
  nearest dollar ("CA$350" for 349.99), except that a price under 50
  cents keeps its cents ("CA$0.45") rather than look free; the product page and orders keep
  the exact price. `<.collection_card name image navigate>` takes plain
  values (not a category), so it serves both site categories and an
  artist's own collections; name in a see-through white pill (70%, with
  a slight blur behind it) at the bottom, lighter on the photo than
  solid white. Both go in a `card-grid` (4 across from 1280px, 3 on
  tablets, 2 on phones). Photos have `alt=""` because the name next to
  them already says what they are. The old `product_card` /
  `category_card` stay until their pages are restyled (Phase E). Found
  on the way: at phone width today's header makes the whole page scroll
  sideways (Phase D rebuilds it).
- **Small text pieces (2026-10-16).** `<.section_heading>` (title, with
  an optional `:link` slot on the right that stays on one line, for "See
  all artists ›" or a "Show more categories ›" button); `<.show_more>` (a
  button that looks like a link; the page changes its words and passes
  `aria-expanded`); `<.quiet_link>` (grey, 14px, underlined);
  `<.report_link subject id return_to return_label>` (a quiet link that
  builds the `/flag/...` address itself, so the five pages that write it
  by hand today get shorter in Phase E; still shown to logged-in users
  only, by the page); `<.chip>` (small cream tag, not clickable) and
  `<.filter_chip pressed count>` (large, at least 40px tall, the chosen
  one filled in dark, `aria-pressed`), both in a `chip-row`. Filter
  chips built now rather than with the Shop tab, so the style guide
  shows the whole family (developer's choice). **The ordinary link look
  is a class for now, `text-link`**: making it the look of every `<a>`
  waits for Phase D, when the header (whose links aren't underlined) is
  rebuilt anyway. Not chosen now: a global link rule, which would
  underline the header, footer and old cards at once.
- **Star rating and review (2026-10-16).** `<.star_rating rating count
  look>`: five stars filled up to the average (4.4 = four stars and 40%
  of the fifth), in the muted grey, then the words in one of three looks
  from the mockups: `short` "(25)" (product page, artist header),
  `home` "4.8 · 31 reviews" (home page artist cards), `full` "4.8 out
  of 5 · 31 reviews" (above a list of reviews). Always one decimal
  ("5.0"). With `href` / `navigate` / `patch` it is a link, words
  underlined. Screen readers hear one sentence ("Rated 4.4 out of 5,
  from 25 reviews."). `<.review stars name date text>` takes plain
  values, not a review (three review kinds, each finding the reviewer's
  name its own way), shows "Linda · September 2026", the text (left out
  when empty), an optional `:bought` slot ("· bought *Crow Study*", for
  the artist's page) and a `:report` slot for the page's own
  `<.report_link>`. Reviews go in a `<ul class="review-list">`. The
  star is the app's `hero-star-solid` icon (the same drawing the
  mockups used). Gotchas: daisyUI has its own `.rating`, so our class is
  `star-rating`; and a Tailwind v4 icon's own size beats a width set in
  our CSS, so stars are `1em` wide and sized by the font size of
  `.stars`. Not in this step: the clickable stars for choosing a rating
  in the review forms (Phase E, with those forms), and showing reviews
  on public pages (the flags bundle).
- **Placeholders (2026-10-16).** `<.placeholder what="Following
  artists">` wraps the markup the real feature would have (button, link,
  tab, a line of text). The wrapper is `display: contents`, so the
  layout doesn't change. Pressing anything inside shows a small note,
  "Not built yet: Following artists", just below the pressed element
  (an information message in miniature, floating over the page); the
  next click anywhere, or Esc, closes it. Same pattern as the confirm
  dialog: one note in `root.html.heex` outside the LiveView, a short
  script in `assets/js/app.js` that catches the click before LiveView
  and the browser do (so a link goes nowhere and a button submits
  nothing). No server code, and pages handle no event. `role="status"`
  so screen readers read the note out. Not chosen: a normal message at
  the top (it doesn't show *what* was pressed, and the message column
  belongs to LiveView). `docs/design/placeholders.md` stays empty until
  Phase E puts the first ones on pages. Style guide: "Placeholders".
- **Phase C done** (the old `button_artsy`, `product_card` and
  `category_card` go as their pages are restyled in Phase E). Next:
  Phase D, the page frame.

## Phase D: the page frame

In `layouts.ex` / `root.html.heex`: header (logo, wordmark, search,
links), category bar, water background (header and sides), footer, and
where messages appear (and how warnings and errors look: see the
message trial in Phase C's notes; remove the trial afterwards). Also
make the `text-link` look the look of every link (see "Small text
pieces" in Phase C's notes), with header, footer and cards switching it
off. The logo waits for the final version from the
developer's daughter; the current draft is used until then.

### Phase D steps and decisions (2026-10-16)

Six steps, each its own commit, with screenshots at computer and phone
width:

1. **Messages: final look and place.** Decided as leaned in the trial:
   **success and information tinted; warnings and errors solid** (filled
   with the kind's colour, white words); **all messages "higher up"**, the
   column starting a quarter of the way down the window, with a soft
   shadow. These are now the only rules (`.msg-warning`, `.msg-error`,
   `.msg-column` in `app.css`); the switches, the script in
   `root.html.heex`, `Layouts.dev_routes?/0` and the trial rules are gone.
2. **Header.** One header instead of today's two rows (the small account
   row in `root.html.heex` and the big header in `navlayout`): logo draft,
   "localpalette" wordmark with its wave (letters built by the server, no
   script), search box (a `<.placeholder>`: search isn't built), links,
   phone layout from the mockup. The test "Holiday sale" banner goes. Also
   fixes `artsy_wide` (admin tables), which doesn't pass `current_scope`,
   so its header acts as if nobody is logged in.
   - **Links for visitors:** About us · Artists · Offer art · Log in ·
     Register (as in the mockup).
   - **Links when logged in** (decided): plain links, no drop-down menus
     (fiddly for older users): About us · Artists · Messages · Orders ·
     Your shop (artists only, in place of "Offer art") · Admin (admins
     only) · Account. "Account" leads to the settings page, which gets
     "Log out". The unread and pending-review dots stay.
   - **Admin and vendor pages** (decided): the same header everywhere (no
     more grey admin and blue vendor headers); admin pages get a slim
     strip under it saying "Admin". Vendor pages need no mark.
3. **Category bar**, starting under the wordmark, with "«" / "»" on phones.
4. **Water background** behind the header and in the side margins.
5. **Footer** as in the mockup; links to pages that don't exist yet are
   placeholders.
6. **The ordinary link look for every link**; header, footer and cards
   switch it off; the `text-link` class is no longer needed.

## Phase E: pages, one at a time

Artist page → product page → home, then the remaining public pages,
then vendor and admin pages (these mostly need Phase 0's buttons,
forms and messages, less of the gallery look). Each page: restyle with
existing data, screenshots at computer and phone width, the
developer's review, commit. Fixed colours left in each file (about
100 in 10 files) are replaced with theme names as it is restyled.

Feature work found along the way goes into `NOTES.md`, not into the
restyling commits.
