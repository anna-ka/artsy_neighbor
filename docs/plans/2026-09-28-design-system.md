# Design system + branding (step 1 of the Order of work)

Status: artist-page mockup in progress (see "Progress" at the end).
This is a living document — visual decisions will be revisited, and
this file should be updated whenever one changes.

## Goal

Give LocalPalette a calm, warm, neighbourly look that lets the artwork
be the colour on the page, and build it so that colours, shapes and
fonts can be changed later in one place.

## Audience (guiding principle)

Launch city is Victoria, BC. Many artists will be over 60, a good share
over 50, likely most over 40. Intuitive and easy over flashy:

- Comfortable text size (body at least 16px, probably larger) and
  strong contrast — no pale-grey-on-white text.
- Large click targets, on phones too.
- Buttons labelled with words, not icon-only.
- Nothing that only works on hover (tablets and phones have no hover).
- Familiar patterns, few steps, clear confirmations.
- No sales pressure: no countdown timers, "hurry" banners, or pop-ups.

## Storefront first (guiding principle, agreed 2026-10-05)

The site should look like a beautiful storefront. People come to look at
and buy art; reading (bios, descriptions) matters but is secondary.
Layout priority: show as many of the artist's works as possible without
scrolling, at a size where the art can actually be seen.

## Direction

Artsy's calm, mostly black-and-white base, warmed up and softened:

- **Colour comes from the art and the logo.** The site itself stays
  quiet — warm white background, near-black text. The logo's palette
  dots are the only bright colour, with at most a little emphasis
  elsewhere.
- **Warmth:** a warm white background, leaning creamy. How much cream
  is not decided — the mockups show a few levels to compare. Creamy
  tones can also be used for buttons and panels.
- **Distinct lines, not harsh ones.** Keep clear, visible lines between
  sections (like Artsy), but with rounded corners and soft shapes
  instead of Artsy's sharp angular framing.
- **Curves like waves:** rounded corners, pill-shaped buttons and search
  box, round artist photos, and an occasional soft wave-shaped divider
  between page sections (echoing the seal's curve in the logo) — used
  sparingly.
- **Neighbourly, not commercial:** the artist's face, name, and their own
  words close to every artwork ("by a neighbour"); a clearly labelled
  "Message" button.

## What we take from the reference sites

(Screenshots are in `priv/static/images/screenshots/`, gitignored — on
the developer's laptop only.)

- **Artsy:** the quiet black-and-white frame; its product page's large
  text, space, and one clear main button. Not: the angular framing.
- **Dribbble (Sable):** warm cream tones, rounded search box, round
  category pictures. Not: tiny grey text and small-caps labels; the
  "luxury shop" commercial feel.
- **Ярмарка Мастеров (Livemaster):** the artist card (photo, name,
  location, short greeting), a labelled "Message" button, the artist's
  own voice on the profile. Calmer and less crowded than theirs.
- **Novica:** makers' faces, and the artist's name shown and linked on
  each product.
- **Redbubble:** big, clearly labelled option buttons. Not: timers, sale
  banners, urgency.

## Logo and colours

- Logo by the developer's daughter; drafts so far are concept only.
  Kept elements: circular, a local animal (a seal), a painter's
  palette. Draft 1 (separate paint dots) likely works better as a small
  favicon than draft 2 (colour brushed onto the seal).
- The seal's dusty slate blue-violet is a candidate for the site's quiet
  second colour (links, small accents).
- The five palette colours (red, orange, green, blue, purple) are
  reserved for the logo and, at most, very small touches.

## Making later changes easy

Visual decisions will change for a while, so everything visual is
defined once and referred to by name:

1. **All colours live in the theme** — the DaisyUI theme block in
   `assets/css/app.css`. Templates use theme names (`bg-base-100`,
   `text-base-content`, `btn-primary`, `border-base-300`), never fixed
   colours (`bg-white`, `text-gray-600`, `#A41C42`). Changing a colour
   is then one line in one file.
2. **Shapes and sizes live in the theme too** — corner roundness, line
   thickness, and the fonts are also theme settings, so "rounder" or
   "thinner lines" is one change.
3. **Shared components** — buttons, cards, the artist card, product
   tiles, the wave divider are built once in `core_components.ex` /
   `custom_components.ex`, and every page uses them.
4. **A style guide page** (dev only, e.g. `/dev/styleguide`) showing
   every colour and component on one page, so a theme change can be
   judged at a glance before looking at real pages.
5. Today about 100 fixed colours remain, in 10 files; they are replaced
   with theme names as each page is restyled.

## Mockups

- Static HTML files in `docs/design/mockups/` (committed), with small
  copies of seed images alongside. Viewed in a browser; Claude takes
  Playwright screenshots for review.
- Each mockup uses the same named colour settings as the real theme, so
  a picked direction carries over directly.
- Order: **artist page** first, then **product page**, then **home**.
  Each at computer and phone width.
- 2–3 directions, mainly differing in how much cream, how strong the
  lines are, and how much of the seal slate colour appears.

## Mobile and a future phone app

The site is built mobile-friendly now. A real phone app is wanted in
the near future; how (an installable web app, LiveView Native, or a
separate app talking to the server) is a later decision. Designing
mobile-first now helps whichever route is picked.

## Open decisions

- Exact background colour (how much cream).
- Fonts (one clean sans-serif throughout, or a warmer serif for
  headings).
- Final logo.

## Progress

### Where we stopped (2026-09-28)

Working on `docs/design/mockups/artist-page.html` (artist page, the
first of three mockups). Decided so far:

- **Layout follows the current artist page:** large square photo on the
  left (half the width) with thumbnails under it instead of carousel
  arrows; on the right the name, location, Mediums, About the artist,
  Delivery options, then "Contact artist" / "View shop". Below:
  Collections, then More works (a grid, not a carousel), then the
  footer. "Report a concern about this artist" is a small right-aligned
  link at the bottom, just above the footer.
- **Colours: Coastal (C)** is the favourite — warm white page, seal
  slate for the main button and accents. Gallery and Cream stay in the
  mockup switcher for comparison.
- **Text:** body 16px (18px felt too big). Location under the name is
  smaller (14px); more space (32px) between Mediums / About / Delivery.
- **Artist photo:** soft shadow tinted with the text colour, no outline.
- **Artworks sit on neutral grey mats** (`#ECECEC`, like Artsy) and are
  shown whole, not cropped. Collections use the same mats. The mat is
  deliberately neutral, independent of the colour scheme.
- **Dividers** are content-width, not full-width. Two sections, two
  dividers.

Added 2026-10-01 (Gallery colours now the default in the mockup):
logo in the screen's top-left corner, 50% larger; smaller search box
on the right with a "Search" button; tall 7:10 artist photo with
matching centred thumbnails; and an **artist motto** line under the
name ("Oils with a splash"), 18px. The motto will need a new optional
Artist field (separate from the existing temporary `announcement`).
Also: header links, categories and search all 15px, regular weight;
all buttons have 10px corners instead of pills (chips and collection
labels still pills); the artist section is 80% of the screen width
(the developer likes this width), with a much smaller artist photo.

2026-10-02: photo fixed at 309px wide (7:10), 72px from the text;
thumbnails replaced by a carousel (arrows + dots on the photo);
6-line bio with "Show full bio ›" / "Show less ‹" (labels settled
2026-10-05); Delivery options moved off this
page (they belong on the shop page); body text 15px; dividers are
straight lines at the 80% width. **Featured works** (chosen by the
artist — see `NOTES.md` #23) now come right after the artist section,
then Collections; both use the 80% width and the same tile size.

**(Resolved 2026-10-02) Paused mid-change (2026-10-01):** the artist section has a large
empty gap between the small photo and the details, because the photo
column is still half the section. Next: give the photo a fixed size
(about 240 × 340px), let its column fit the photo, and start the
details right beside it; then tidy the remaining empty space. Also
still open: whether Collections / More works should match the 80%
width, so the page has one left edge.

2026-10-05: **faint water background** — "we live on an island" —
underlines the local, coastal feel without clutter. A calm photo of a
wave (Matt Hardy, Unsplash; free licence) is used as a *luminance mask*
over the seal-slate theme colour at 22% strength, so only the site's
own colour shows, never the photo's blue. It sits behind the header and
category bar (fading into the page colour towards the bottom) and in
the side margins outside the 80% content (fixed, fading towards the
content). Buttons are Switzer Regular. Settings: `--hat-tint`,
`--hat-opacity`, `--hat-position`, `--hat-fade-start`, `--sides-opacity`,
`--sides-position`. Alternatives kept as switches: `?hat=ripples`,
`?sides=sea` (busier), `?hat=none`, `?sides=none`.
- **View the mockup through the local server**
  (`python3 -m http.server 8765` in the repo root, then
  http://127.0.0.1:8765/docs/design/mockups/artist-page.html):
  browsers block CSS masks on pages opened straight from disk.
- Web-size copies live in `priv/static/images/` (gitignored):
  `hat-water-wave.jpg` (2400×1600, ~570 KB; may still be replaced by
  a better photo; before real use, shrink and compress it, e.g. ~1600px
  wide, greyscale, lower JPEG quality, since only its brightness shows
  faintly),
  `hat-water-ripples.jpg`, `sides-water-sea.jpg`.
- On phones, use the full width and drop the side water (the 80% width
  wastes space there).

2026-10-05 (later): **page width** — content (and the header, which now
lines up with it above phone width) is 80% of the screen but stops
growing at **1600px** (`--content-width`); 1200px felt too narrow on
the developer's big monitor and MacBook. `?width=1200 | 1400 | none`
compares. The bio is capped at **100 characters per line** (70 left a
weird empty strip). Strictly fixed widths per device type were
considered and not used: window widths vary too much within "laptop"
and "desktop"; 80%-up-to-1600px already behaves as fixed on big
screens. Next: shorten the artist section so works show in the first
screen; then try 3 works per row on laptops / 4 on big screens (the
featured-work images felt small).

2026-10-07: bio back to plain left alignment (centred + justified tried,
looked bad). Gap between artist photo and text grows with the screen:
`clamp(72px, 6vw, 160px)` (`?gap=72` = old). **Works per row:** 4 from
1280px up, 3 on tablets/small laptops, 2 on phones (collections the
same); a 4th featured work wrapping alone on tablets is accepted for
now. **Featured-work tiles are now cropped to fill a landscape 4:3
area inside the mat, like collections** (`?tiles=whole` = old
uncropped version) — portrait tiles and other layouts (square crop,
equal-height rows) were discussed and put off as too many options for
now; the product page must show the whole work. Upload checks and
automatic resizing: `NOTES.md` #24. Idea for later: line the artist
photo and text up with the works grid columns below.
**No more grey mat (for now, may revisit):** featured-work and
collection tiles have just a thin outline in the divider colour, with
the image filling the tile. `?mat=gap` (8px page-coloured gap inside
the line) and `?mat=grey` (old mat) compare.
**Header back to full screen width** (logo near the left screen edge,
links near the right), not lined up with the content;
`?header=aligned` shows the aligned version.
Artist photo 309px → **280px** wide, bio preview 4 → **3 lines**, to
pull the featured works up a little. More room is expected once the
logo is final and the header/nav bar can be made more compact.
**Phone layout:** full width with 16px margins, no side water; small
artist photo (110px) beside the name, motto, area and tags, with the
bio and buttons full width below, so the "Featured works" heading shows
in the first screen. The category bar gets "»" at its right end and
"«" at its left once scrolled (tap scrolls the bar; each hides when
there is nothing more that way). Header links (Log in first, then
Artists, Offer art, Messages) get their own full-width row under the
search box — tried a scrolling "»" strip beside the logo first, too
cramped; a "Menu" button is the alternative if space gets tight.
Revisit with the final logo/header.

2026-10-08: **page width is now simply 80% of the screen, with no upper
limit** (replaces the 1600px cap from 2026-10-05 — 80% feels more
spacious on the developer's big monitor). `?width=1200 | 1400 | 1600`
show capped versions. The bio stays capped at 100 characters per line.
On very wide screens (ultrawide / 4K at 100% scaling) the works tiles
get very large; revisit if testers on such screens find it odd.
**Vertical rhythm:** one `--section-gap` (48px; 32px on phones) above
and below every divider line and above the footer; 24px between the
last tiles and "Report a concern". The footer now uses the content
width (80%), lining up with everything above. Space between the header
and the artist section (32px) was left alone — revisit with the final
logo and "hat".

Tried and dropped: full-width wavy dividers; a wave between every
section; the fonts in the first round (Inter / Lora / Nunito Sans) and
18px text; a smaller, fixed-width artist photo; drawn SVG wave lines as
a header background (looked like wallpaper).

### Next steps

1. **Explore the Gallery (A) colours further.** They are more neutral,
   which may be more practical for art: a neutral frame flatters every
   artwork, while slate can clash with some. Develop Gallery on the
   current layout (it may borrow a touch of slate, e.g. for the main
   button) and compare it with Coastal side by side.
2. **Dividers: straight lines for now** (decided 2026-10-02), spanning
   the artist section's 80% width. **Keep the spiral crest in mind:**
   the developer likes it but hasn't found a good place for it yet. It
   is a straight line that, at its right end, rises (never dipping
   below the line), loops back over to the left and winds inward
   counter-clockwise — like a scroll or a curling wave, echoing the
   seal's curve in the logo. It is drawn once as the `crest-spiral`
   symbol in `artist-page.html` (size via `--spiral-size`, now 32px)
   and can be shown again with `?divider=spiral`. Possible future uses:
   a small motif on section headings, empty states, or the footer.
3. **Fonts: chosen (2026-10-02), refine as we go.** Pairing found on
   artgalleria.com: **Sentient** (serif, Fontshare) for titles and
   **Switzer** (sans-serif, Fontshare) for everything else, plus
   **Spline Sans Mono** (Google Fonts) for one small label.
   - Sentient Light (300): artist name 36px, section titles 26px;
     motto 20px in Light *italic*.
   - Nav links and categories: **Switzer Regular 400 at 15px**, matching
     the search box and button (chosen 2026-10-05, after going back and
     forth with Sentient Regular 16px and Switzer Light 16px — still a
     close call; `?nav=serif` shows the Sentient version).
   - Switzer: bio Light 300 at
     15px (a bit hard on the eyes — revisit); buttons **Regular 400**
     (chosen 2026-10-05 over Medium; `?buttons=medium` to compare);
     artwork titles and small headings Bold; other text Regular 15px.
   - Spline Sans Mono: location line, 12px capitals.
   - Use the **variable** font files in the real app (one file per
     style holds all weights).
   - **License:** Fontshare's ITF Free Font License allows self-hosting
     on our own site but **not redistributing the files** (including
     via a repository). The trial files live in
     `docs/design/mockups/fonts/` (gitignored); each developer
     downloads their own copy. Re-check how to ship them with the app.
   - Mockup switches: `?nav=serif` (Sentient nav), `?motto=upright`,
     `?fonts=plain` (old system font).
   - 2026-10-05: compared the bio with Avenir-like fonts (inspired by
     artevo-consulting.com, all Avenir Next): `?bio=switzer` (Regular
     16px), `?bio=satoshi`, `?bio=general`. Kept Switzer Light 15px for
     now; most of the readability gain came from Regular at 16px, so
     that is the first thing to try if the bio feels hard to read.

4. **Real photo** of the developer painting, to replace the
   watermarked stock photo (`artist-hand.jpg`).
5. Small open question: footer and side panels are still slate-tinted;
   maybe make them neutral too.
6. Then the **product page** mockup, then **home**, then turn the
   result into the real DaisyUI theme and shared components.
