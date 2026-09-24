defmodule ArtsyNeighbor.Repo.Migrations.AddStatusToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :status, :string, default: "active", null: false
      add :status_changed_at, :utc_datetime
    end
  end
end
