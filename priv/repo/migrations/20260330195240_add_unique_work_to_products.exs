defmodule ArtsyNeighbor.Repo.Migrations.AddUniqueWorkToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :unique_work, :boolean, default: false, null: false
    end
  end
end
