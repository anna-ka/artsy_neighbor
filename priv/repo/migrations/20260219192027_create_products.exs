defmodule ArtsyNeighbor.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :title, :string
      add :descr, :text
      add :details, :text
      add :price, :decimal, precision: 10, scale: 2
      add :artist_id, references(:artists, on_delete: :nilify_all)
      add :category_id, references(:categories, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:products, [:artist_id])
    create index(:products, [:category_id])
  end
end
