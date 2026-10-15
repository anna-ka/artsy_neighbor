# How styling works in Artsy Neighbor

A guide for someone who knows programming but not much HTML or CSS.
It explains what decides how the site looks, where each part lives, and
how a change travels from one place to every page.

## 1. The three languages in a web page

Every page the browser shows is made of three things:

- **HTML**: the *content and structure*. "Here is a heading, here is a
  picture, here is a button that says *Send message*." It says nothing
  about colours or sizes.
- **CSS**: the *looks*. "Headings are 26px, in Sentient Light; buttons
  have 10px rounded corners and a dark background."
- **JavaScript**: *behaviour in the browser*. We use very little,
  because LiveView handles most behaviour on the server.

In Phoenix we don't write HTML files directly. We write **HEEx
templates** (the `~H"""..."""` blocks in `.ex` files), which are HTML
with Elixir mixed in. Phoenix turns them into plain HTML before sending
them to the browser.

## 2. How HTML and CSS connect: classes

An HTML element can carry one or more **class names**:

```html
<a class="btn btn-primary" href="/artists/3">Send message</a>
```

A **CSS rule** then says what everything with a given class looks like:

```css
.btn-primary { background: #1E1C19; color: white; }
```

The class name is the only link between the two. The HTML says *what
kind of thing* this is ("a main button"), and the CSS says *what that
kind of thing looks like*. Change the rule, and every element with that
class changes at once.

## 3. CSS variables: named values

CSS lets us give a value a name and use the name everywhere:

```css
--color-primary: #1E1C19;          /* define the name once */
.btn-primary { background: var(--color-primary); }   /* use it */
```

Names starting with `--` are **CSS variables**. This is what makes
"change a colour in one place" possible: the colour is written once, as
a variable, and every rule refers to the name instead of `#1E1C19`.

## 4. Tailwind and daisyUI: the two libraries we use

### Tailwind

Tailwind is a large set of ready-made, tiny classes, each doing one
thing. `p-4` adds padding, `text-lg` makes text larger, `flex` puts
things in a row, `md:grid-cols-3` means "three columns on medium
screens and up". You build a layout by stacking them in the template:

```heex
<div class="flex gap-4 p-4">...</div>
```

**Tailwind has a build step.** It reads all our templates, finds every
class name we actually use, and writes just the CSS for those into one
file. While `mix phx.server` runs, it does this automatically after
every save, so normally you never notice it.

- Input (what we edit): `assets/css/app.css`
- Output (generated, never edit): `priv/static/assets/css/app.css`
- Which files it scans for class names: the `@source` lines at the top
  of `assets/css/app.css` (`lib/artsy_neighbor_web` is the important
  one).
- Its settings: `config :tailwind` in `config/config.exs`.

One consequence: a class name has to appear **written out in full**
somewhere under `lib/artsy_neighbor_web`. Tailwind cannot see a class
that is pieced together while the app runs (`"btn-" <> variant`), so
that class never makes it into the CSS file.

### daisyUI

daisyUI is a plugin on top of Tailwind. It adds:

1. **Component classes**: bigger building blocks such as `btn`,
   `btn-primary`, `btn-error`, `alert`, `card`, `badge`, `input`,
   `tabs`, `link`.
2. **Themes**: a theme is a named set of CSS variables (colours, corner
   roundness, line thickness). daisyUI's component classes only use
   those names, never fixed colours. So switching or editing the theme
   restyles every daisyUI component.

The colour names daisyUI expects are worth knowing, because we will use
them everywhere:

| Name | Meaning on our site |
|---|---|
| `base-100` | page background (warm white) |
| `base-200` | panels, cards, footer |
| `base-300` | lines and borders |
| `base-content` | ordinary text |
| `primary` | the main button |
| `secondary` | links, small accents (seal slate) |
| `neutral` | quiet dark elements |
| `info` / `success` / `warning` / `error` | messages and danger (e.g. `btn-error` for "Delete") |

Each colour has a matching `-content` colour for text placed *on* it
(`primary-content` is the text colour on a `primary` button).

In templates these names appear inside class names: `bg-base-200` (base-200
as background), `text-base-content`, `border-base-300`, `btn-primary`,
`text-error`.

The daisyUI library itself lives in `assets/vendor/daisyui.js` and
`assets/vendor/daisyui-theme.js`. We never edit those files.

## 5. Where each part lives

From the bottom layer (raw values) to the top (pages):

| Layer | File | What's in it |
|---|---|---|
| 1. **Theme** | `assets/css/app.css`, the `@plugin "../vendor/daisyui-theme" { ... }` block | Every colour, the corner roundness, line thickness. One theme, "localpalette". |
| 1. **Our extra settings** | `assets/css/app.css`, an `@theme { ... }` block | What daisyUI has no name for: muted text colour, fonts, section spacing, content width. |
| 1. **Fonts** | `assets/css/app.css` (`@font-face` rules) plus the font files | Which font files to load and under what name. (Where the files come from is still open: see the plan.) |
| 2. **Our own CSS classes** | `assets/css/app.css`, at the end | A few rules that are clumsy as Tailwind classes, e.g. the water background, the star rating. Kept short. |
| 3. **Basic components** | `lib/artsy_neighbor_web/components/core_components.ex` | Generated by Phoenix and adapted by us: `<.button>`, `<.input>`, `<.flash>`, `<.table>`, `<.icon>`, `<.header>`. |
| 3. **Our components** | `lib/artsy_neighbor_web/components/custom_components.ex` | Pieces specific to this site: artwork tile, collection tile, star rating, review, section heading, ... |
| 4. **The page frame** | `lib/artsy_neighbor_web/components/layouts.ex` and `layouts/root.html.heex` | `root.html.heex` is the outer `<html>` shell, loaded once: it links the CSS and JS files and fonts. `layouts.ex` has the header, category bar, footer, and the spot where messages ("flash") appear. |
| 5. **Pages** | `lib/artsy_neighbor_web/live/**` | Each page arranges components, plus a few Tailwind classes for layout (`grid`, `gap-6`, ...). Ideally **no colours, fonts or sizes are chosen here.** |
| (lab) | `docs/design/mockups/` | Static mockups where looks are tried out first. Not part of the app. |

### What a component is

A **component** is an Elixir function that returns a piece of HEEx. A page
writes

```heex
<.button variant="primary">Send message</.button>
```

and `core_components.ex` turns it into

```html
<button class="btn btn-primary">Send message</button>
```

The page says *what* it wants ("a main button"); the component decides
*which classes* that means. If we later decide main buttons need another
class, we change one function, not 40 templates.

## 6. How one change travels

Say we want the main button a little warmer:

1. **Theme:** in `assets/css/app.css`, change `--color-primary`.
2. daisyUI's `btn-primary` class uses `--color-primary`, so it changes.
3. `<.button variant="primary">` produces `btn-primary`, so every main
   button changes.
4. Every page that uses `<.button variant="primary">` changes, with no
   edits to the pages.

Say instead we want *all buttons* to have rounder corners: that is
`--radius-field` in the theme. If we want buttons to have a different
*font weight*: that is the `<.button>` component (or a rule in our own
CSS). If one page wants a button placed further right: that is a layout
class on that page only.

**Rule of thumb for where a change goes:**

- A colour, roundness or line thickness → the theme.
- A font, spacing scale, page width → our extra settings (`@theme`).
- How a kind of thing looks everywhere (all buttons, all tiles) → its
  component.
- Where things sit on one page → that page.

## 7. The mockups and the app

The mockups in `docs/design/mockups/` work like a small copy of this
system, without Phoenix:

| Mockup | App |
|---|---|
| Colour variables at the top of `mockup.css` (`--color-primary`, ...) | The theme block in `assets/css/app.css`, **same names** |
| `--font-heading`, `--section-gap`, `--content-width` in `mockup.css` | Our extra settings (`@theme`) in `assets/css/app.css` |
| Classes such as `.btn-primary`, `.card`, `.collection`, `.rating` in `mockup.css` | Components in `core_components.ex` / `custom_components.ex` |
| Header and footer markup copied into each mockup page | The layout in `layouts.ex` |

**The working rule:** look changes are tried in the mockup first. Once we
like one, the same value or rule is copied into the app. Because the
names match, that's usually copying a line. The mockups stay in the repo
for future fine-tuning.

## 8. Messages ("flash")

When something happens, such as "Your message was sent" or "Could not save
the product", Phoenix shows a **flash message**. Where:

- The message itself is set in the Elixir code with `put_flash(socket,
  :info, "...")` or `:error`.
- How it looks and where it appears is the `<.flash>` component in
  `core_components.ex`. Today it uses daisyUI's `toast toast-top
  toast-end` classes, which means **top-right corner, floating over the
  page**. That's why it is easy to miss.
- Where it sits in the page frame is `<.flash_group>` in `layouts.ex`.

So changing how messages appear is a change to two components, not to
every page.

## 9. Glossary

- **Class**: a label on an HTML element that CSS rules attach to.
- **CSS rule**: "elements matching *this* look like *that*".
- **CSS variable**: a named value (`--color-primary`), used with `var()`.
- **Tailwind**: a library of tiny one-job classes, built into one CSS
  file from the class names we use.
- **daisyUI**: a Tailwind plugin with ready-made components (`btn`,
  `alert`, ...) and themes.
- **Theme**: one set of values for daisyUI's variables.
- **Component**: an Elixir function that returns a reusable piece of
  HEEx, called as `<.name ...>`.
- **Layout**: the frame around every page (header, footer, messages).
- **Flash**: a short message shown after an action.
- **Token**: designer's word for a named value like `--color-primary`.
  Same thing as a CSS variable here.
