defmodule ArtsyNeighbor.Repo.Migrations.AddStatusToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :status, :string, default: "available", null: false
    end
  end
end
