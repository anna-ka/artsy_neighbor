defmodule ArtsyNeighborWeb.Plugs.SitePassword do
  @moduledoc """
  One shared username and password in front of the whole site, for the
  private deployment (only the developer and invited testers).

  This is the browser's built-in login box ("HTTP basic auth"), not the
  site's own user accounts. It runs in the endpoint, before static files
  and the router, so no page, image or stylesheet is served without it.

  Turned on by this config (set in `config/runtime.exs` for prod from the
  `SITE_USERNAME` and `SITE_PASSWORD` secrets):

      config :artsy_neighbor, :site_password,
        username: "...",
        password: "..."

  When it isn't set (dev and test), every request passes through.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Application.get_env(:artsy_neighbor, :site_password) do
      nil ->
        conn

      credentials ->
        # Plug.BasicAuth compares the password in constant time and, when it
        # is missing or wrong, answers 401 and stops the request here.
        Plug.BasicAuth.basic_auth(conn,
          username: Keyword.fetch!(credentials, :username),
          password: Keyword.fetch!(credentials, :password),
          realm: "Artsy Neighbor (private)"
        )
    end
  end
end
