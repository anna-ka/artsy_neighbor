defmodule ArtsyNeighbor.Repo.Migrations.CreateProductCollections do
  use Ecto.Migration

  def change do
    create table(:product_collections) do
      add :name,      :string,  null: false
      add :position,  :integer, null: false
      add :artist_id, references(:artists, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:product_collections, [:artist_id])

    # Backfill: create a default "All Works" collection for every existing artist.
    # We use a raw SQL INSERT ... SELECT so this runs as a single statement
    # with no dependency on application code.
    execute """
    INSERT INTO product_collections (name, position, artist_id, inserted_at, updated_at)
    SELECT 'All Works', 1, id, NOW(), NOW()
    FROM artists
    """,
    # Down: remove all collections (table will be dropped anyway, but be explicit)
    ""
  end
end
