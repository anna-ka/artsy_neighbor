defmodule ArtsyNeighbor.Repo.Migrations.CreateBuyersReviewed do
  use Ecto.Migration

  def change do
    create table(:buyers_reviewed) do
      add :order_id,    references(:orders, on_delete: :restrict), null: false
      add :reviewer_id, references(:users,  on_delete: :restrict), null: false
      add :buyer_id,    references(:users,  on_delete: :restrict), null: false
      add :stars,       :integer, null: false
      add :body,        :text

      add :submitted_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:buyers_reviewed, [:order_id])
    create index(:buyers_reviewed, [:buyer_id])
    create index(:buyers_reviewed, [:reviewer_id])
  end
end
