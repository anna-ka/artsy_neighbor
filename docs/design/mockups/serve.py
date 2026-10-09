"""Local server for the design mockups.

Run from anywhere:  python3 docs/design/mockups/serve.py
Then open:          http://127.0.0.1:8765/docs/design/mockups/artist-page.html

Like `python3 -m http.server`, but:
- tells the browser never to cache, so edits to the shared mockup.css
  and mockup.js always show up on a normal reload;
- only listens on this computer (127.0.0.1), not the local network.
"""

import functools
import http.server
import pathlib

PORT = 8765
# Serve the repo root, so the mockups can reach images in priv/static/.
REPO_ROOT = pathlib.Path(__file__).resolve().parents[3]


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


handler = functools.partial(NoCacheHandler, directory=str(REPO_ROOT))
server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), handler)
print(f"Serving {REPO_ROOT} at http://127.0.0.1:{PORT}/docs/design/mockups/")
server.serve_forever()
