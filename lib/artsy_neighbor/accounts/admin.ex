defmodule ArtsyNeighbor.Accounts.Admin do

  @moduledoc """
  The Admin schema, which represents users with administrative privileges in the system.
  """

  use Ecto.Schema

  schema "admins" do
    belongs_to :user, ArtsyNeighbor.Accounts.User

    timestamps(updated_at: false)
  end

end
