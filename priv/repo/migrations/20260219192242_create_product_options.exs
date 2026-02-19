defmodule ArtsyNeighbor.Repo.Migrations.CreateProductOptions do
  use Ecto.Migration

  def change do
    create table(:product_options) do
      add :name, :string
      add :descr, :text
      add :values, {:array, :string}
      add :product_id, references(:products, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:product_options, [:product_id])
  end
end
