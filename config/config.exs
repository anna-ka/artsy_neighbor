# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :artsy_neighbor, :scopes,
  user: [
    default: true,
    module: ArtsyNeighbor.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: ArtsyNeighbor.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :artsy_neighbor,
  ecto_repos: [ArtsyNeighbor.Repo],
  generators: [timestamp_type: :utc_datetime]

# Where uploaded images are stored (see ArtsyNeighbor.Storage).
# Step c of the image-storage plan switches prod to Tigris.
config :artsy_neighbor, ArtsyNeighbor.Storage, backend: ArtsyNeighbor.Storage.Local

# How many photos one machine processes at the same time, and how long
# (milliseconds) a photo waits for its turn before the artist is told
# the site is busy (see ArtsyNeighbor.Images.Limiter). Processing a
# photo takes a lot of memory; decide the final numbers on the real
# server (NOTES, step 2c).
config :artsy_neighbor, ArtsyNeighbor.Images.Limiter,
  max_concurrent: 2,
  wait_ms: 30_000

# Configure the endpoint
config :artsy_neighbor, ArtsyNeighborWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ArtsyNeighborWeb.ErrorHTML, json: ArtsyNeighborWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ArtsyNeighbor.PubSub,
  live_view: [signing_salt: "V4WV4CyD"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :artsy_neighbor, ArtsyNeighbor.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  artsy_neighbor: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  artsy_neighbor: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Use tzdata for timezone conversions (e.g. UTC → America/Vancouver for display).
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Default display timezone. Change this when per-user timezones are implemented.
config :artsy_neighbor, :timezone, "America/Vancouver"

# The name shown in system/admin messages and emails. Change here to rebrand.
config :artsy_neighbor, :platform_name, "Artsy Neighbour"

# The home page's hero: a detail of one work, chosen by hand for now. The
# credit on the picture (title, artist, area) comes from the work itself.
# See "Home page" in docs/plans/2026-10-15-theme-and-components.md.
# The work's id is set per environment (dev.exs, runtime.exs), because ids
# differ between databases: with the wrong id the picture would carry
# another artist's name. Without an id the picture shows with no credit.
config :artsy_neighbor, :home_hero,
  image: "/images/site/hero-protectress.jpg",
  alt: "Detail of the painting Protectress: a wolf's face beside a sleeping woman",
  product_id: nil

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
