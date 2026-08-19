defmodule ArtsyNeighbor.Repo.Migrations.CreateProductReviews do
  use Ecto.Migration

  def change do
    create table(:product_reviews) do
      add :order_id,    references(:orders,   on_delete: :restrict), null: false
      add :product_id,  references(:products, on_delete: :restrict), null: false
      add :reviewer_id, references(:users,    on_delete: :restrict), null: false
      add :stars,       :integer, null: false
      add :body,        :text

      add :submitted_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:product_reviews, [:order_id, :product_id])
    create index(:product_reviews, [:product_id])
    create index(:product_reviews, [:reviewer_id])
  end
end
