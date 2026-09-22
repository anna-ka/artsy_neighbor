defmodule ArtsyNeighbor.Repo.Migrations.AddStatusToCategories do
  use Ecto.Migration

  def change do
    alter table(:categories) do
      add :status, :string, default: "active", null: false
      add :status_changed_at, :utc_datetime
    end
  end
end
