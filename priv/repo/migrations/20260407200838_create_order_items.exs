defmodule ArtsyNeighbor.Repo.Migrations.CreateOrderItems do
  use Ecto.Migration

  def change do
    create table(:order_items) do
      add :quantity, :integer, null: false, default: 1
      add :unit_price, :decimal, precision: 10, scale: 2, null: false
      add :product_title, :string, null: false
      add :return_policy_snapshot, :string
      add :selected_options, :map,  default: %{}
      add :order_id, references(:orders, on_delete: :nothing), null: false
      add :product_id, references(:products, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end



    create index(:order_items, [:order_id])
    create index(:order_items, [:product_id])
  end
end
