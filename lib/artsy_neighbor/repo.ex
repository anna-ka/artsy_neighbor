defmodule ArtsyNeighbor.Repo do
  use Ecto.Repo,
    otp_app: :artsy_neighbor,
    adapter: Ecto.Adapters.Postgres
end
