defmodule ArtsyNeighbor.Repo.Migrations.AddPickupFieldsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :pickup_date,         :string
      add :pickup_time,         :string
      add :pickup_address,      :string
      add :pickup_instructions, :string
      add :pickup_scheduled_at, :utc_datetime
    end
  end
end
