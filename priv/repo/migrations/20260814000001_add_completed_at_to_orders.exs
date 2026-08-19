defmodule ArtsyNeighbor.Repo.Migrations.AddCompletedAtToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :completed_at, :utc_datetime
    end
  end
end
