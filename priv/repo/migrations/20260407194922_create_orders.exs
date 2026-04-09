defmodule ArtsyNeighbor.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders) do
      add :status, :string, null: false, default: "requested"
      add :delivery_method, :string, null: false, default: "pickup"
      add :delivery_address, :string
      add :subtotal, :decimal, precision: 10, scale: 2
      add :platform_fee, :decimal, precision: 10, scale: 2
      add :total, :decimal, precision: 10, scale: 2
      add :complete_token, :string
      add :complete_token_at, :utc_datetime
      add :conversation_id, references(:conversations, on_delete: :nothing), null: false
      add :buyer_id, references(:users, on_delete: :nothing), null: false
      add :artist_id, references(:artists, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end



    create index(:orders, [:conversation_id])
    create index(:orders, [:status])
    create index(:orders, [:buyer_id])
    create index(:orders, [:artist_id])
  end
end
