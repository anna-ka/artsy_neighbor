# ArtsyNeighbor

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Machine setup (Mac)

Things outside the repo that the project needs, beyond Elixir/Erlang
and Postgres.app:

* **libvips with HEIC support** (image resizing, iPhone photos):
  `brew install vips`, and in `~/.zshrc`:
  `export VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS`.
  This must be set *before* `vix` compiles; if it wasn't, run
  `mix deps.clean vix && mix deps.compile vix` in a new terminal.
  `test/artsy_neighbor/image_setup_test.exs` fails if this is wrong.
* **Tailwind on macOS 27**: the downloaded binary must be re-signed
  after every fresh download, or macOS kills it and the stylesheet
  silently stops rebuilding:
  `codesign --force -s - _build/tailwind-macos-arm64*`.

The deploy runbook for the private preview is `docs/deploy.md`.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
