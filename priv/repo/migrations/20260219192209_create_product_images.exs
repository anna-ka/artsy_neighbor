defmodule ArtsyNeighbor.Repo.Migrations.CreateProductImages do
  use Ecto.Migration

  def change do
    create table(:product_images) do
      add :path, :string
      add :position, :integer
      add :product_id, references(:products, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:product_images, [:product_id])
  end
end
