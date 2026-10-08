# Design mockups

Static HTML mockups for the design-system step — see
`docs/plans/2026-09-28-design-system.md`. They are not part of the app.

**To view:** start a local server from the repo root
(`python3 -m http.server 8765`) and open
http://127.0.0.1:8765/docs/design/mockups/artist-page.html. Opening the
file directly almost works, but the browser then blocks the water
backgrounds. Add `?direction=b` (or another switch) to the address to
compare versions. Make the window narrow to see the phone layout.

**Images** point to `priv/static/images/` and `priv/static/uploads/`,
which are gitignored — they only show on the developer's machine.

**Shared files:** `mockup.css` and `mockup.js` hold everything the pages
have in common (colours, fonts, header, buttons, tiles, footer, URL
switches, carousel). Each page links them and adds only its own styles
and script. The header and footer markup is copied into each page.

**Colours, corners, lines and fonts** are named settings (CSS variables)
at the top of `mockup.css`, one block per direction. The page only uses the
names, the same way the real DaisyUI theme will — so trying a different
cream is a one-line change in that block.

The artist ("Maren Holt") and her texts are invented for the mockup.
