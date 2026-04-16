defmodule ArtsyNeighbor.Repo.Migrations.AddReadTimestampsToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      # Tracks when each party last opened this conversation.
      # nil means they have never opened it — treated as "unread" in queries.
      add :buyer_last_read_at,  :utc_datetime
      add :vendor_last_read_at, :utc_datetime
    end
  end
end
