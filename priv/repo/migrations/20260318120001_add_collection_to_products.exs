defmodule ArtsyNeighbor.Repo.Migrations.AddCollectionToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      # Which vendor collection this product belongs to.
      # Nullable: a product may not be assigned to any collection.
      # nilify_all: if the collection is deleted, products are unassigned (not deleted).
      add :collection_id, references(:product_collections, on_delete: :nilify_all), null: true

      # Display order within the collection. Nullable: unpositioned products sort last.
      add :position, :integer, null: true
    end

    create index(:products, [:collection_id])

    # Backfill: assign all existing products to their artist's default "All Works" collection.
    # This runs after the product_collections table and "All Works" rows already exist
    # (created by the previous migration).
    execute """
    UPDATE products
    SET collection_id = (
      SELECT id FROM product_collections
      WHERE artist_id = products.artist_id
        AND name = 'All Works'
      LIMIT 1
    )
    WHERE collection_id IS NULL
    """,
    # Down: nothing needed — the column is dropped when this migration is reversed
    ""
  end
end
