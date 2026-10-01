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

Tried and dropped: full-width wavy dividers; a wave between every
section; the fonts in the first round (Inter / Lora / Nunito Sans) and
18px text; a smaller, fixed-width artist photo.

### Next steps

1. **Explore the Gallery (A) colours further.** They are more neutral,
   which may be more practical for art: a neutral frame flatters every
   artwork, while slate can clash with some. Develop Gallery on the
   current layout (it may borrow a touch of slate, e.g. for the main
   button) and compare it with Coastal side by side.
2. **Decide the divider:** straight lines, or the small spiral crest
   (counter-clockwise, sitting on the line — drawn once and reused, so
   it could become a small repeating motif). Both are in the mockup's
   "Dividers" switch. Still open: how the spiral would repeat around
   the site.
3. **Font comparison page:** 4–5 candidate fonts side by side, at a
   couple of sizes. The mockup uses a plain system font until then.
4. **Real photo** of the developer painting, to replace the
   watermarked stock photo (`artist-hand.jpg`).
5. Small open question: footer and side panels are still slate-tinted;
   maybe make them neutral too.
6. Then the **product page** mockup, then **home**, then turn the
   result into the real DaisyUI theme and shared components.
