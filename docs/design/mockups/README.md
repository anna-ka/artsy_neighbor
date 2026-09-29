# Design mockups

Static HTML mockups for the design-system step — see
`docs/plans/2026-09-28-design-system.md`. They are not part of the app.

**To view:** open a file (e.g. `artist-page.html`) directly in a browser.
The buttons in the dark bar at the top switch between design directions
(or add `?direction=b` to the address). Make the window narrow to see
the phone layout.

**Images** point to `priv/static/images/` and `priv/static/uploads/`,
which are gitignored — they only show on the developer's machine.

**Colours, corners, lines and fonts** are named settings (CSS variables)
at the top of each file, one block per direction. The page only uses the
names, the same way the real DaisyUI theme will — so trying a different
cream is a one-line change in that block.

The artist ("Maren Holt") and her texts are invented for the mockup.
