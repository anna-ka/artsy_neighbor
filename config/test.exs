import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :argon2_elixir, t_cost: 1, m_cost: 8

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :artsy_neighbor, ArtsyNeighbor.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "artsy_neighbor_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :artsy_neighbor, ArtsyNeighborWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "+d6MZ8BSHBBRWBMSwQvOH+pfXkrYMwMAhD7NQatAla8zE6mchz4oHdSxeFWlPO1K",
  server: false

# Uploaded images go to a temporary folder in tests, not priv/.
config :artsy_neighbor, ArtsyNeighbor.Storage.Local,
  public_dir: Path.join(System.tmp_dir!(), "artsy_neighbor_test/uploads"),
  private_dir: Path.join(System.tmp_dir!(), "artsy_neighbor_test/private_uploads")

# Photos checked on pick wait in a temporary folder per page
# (ArtsyNeighbor.Images.PreparedFolders): the tests' own, apart from the
# dev server's, and deleted straight after a page closes rather than a
# minute later, so the tests can check it.
config :artsy_neighbor, ArtsyNeighbor.Images.PreparedFolders,
  base_dir: Path.join(System.tmp_dir!(), "artsy_neighbor_test/prepared"),
  delete_after_ms: 0

# In test we don't send emails
config :artsy_neighbor, ArtsyNeighbor.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
