defmodule ArtsyNeighbor.Repo.Migrations.AddStatusToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :status, :string, default: "active", null: false
      add :status_changed_at, :utc_datetime
    end
  end
end
