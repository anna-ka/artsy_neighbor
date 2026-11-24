defmodule ArtsyNeighbor.Repo.Migrations.AddIsDefaultToProductCollections do
  use Ecto.Migration

  # Every artist has one default collection, which works with no other
  # collection go into. Until now it was recognised only by its name,
  # "Uncategorized", so renaming it, or making a second collection with
  # that name, broke things (audit S-4). From now on the is_default
  # column says which one it is, and the artist may rename it.
  #
  # Steps:
  #   1. Add the column (false for every row).
  #   2. Mark each artist's oldest "Uncategorized" collection as the
  #      default.
  #   3. Give every artist who still has no default a new one.
  #   4. Put works with no collection into their artist's default.
  #   5. A unique index: at most one default per artist.
  #
  # It can't fail on odd data: an artist with two "Uncategorized"
  # collections gets the older one as the default (step 2), and one with
  # none gets a new one (step 3). On 2026-11-23 every artist on dev had
  # exactly one.
  def up do
    alter table(:product_collections) do
      add :is_default, :boolean, null: false, default: false
    end

    # Step 2. min(id) = the oldest, if an artist has two with that name.
    execute """
    UPDATE product_collections
    SET is_default = true
    WHERE id IN (
      SELECT min(id)
      FROM product_collections
      WHERE name = 'Uncategorized'
      GROUP BY artist_id
    )
    """

    # Step 3. Placed after the artist's other collections.
    execute """
    INSERT INTO product_collections (name, position, artist_id, is_default, inserted_at, updated_at)
    SELECT
      'Uncategorized',
      COALESCE((SELECT max(c.position) FROM product_collections c WHERE c.artist_id = a.id), 0) + 1,
      a.id,
      true,
      now() AT TIME ZONE 'utc',
      now() AT TIME ZONE 'utc'
    FROM artists a
    WHERE NOT EXISTS (
      SELECT 1 FROM product_collections c WHERE c.artist_id = a.id AND c.is_default
    )
    """

    # Step 4.
    execute """
    UPDATE products p
    SET collection_id = c.id
    FROM product_collections c
    WHERE p.collection_id IS NULL
      AND c.artist_id = p.artist_id
      AND c.is_default
    """

    # Step 5. "WHERE is_default": the index only covers default rows, so
    # an artist can have any number of other collections.
    create unique_index(:product_collections, [:artist_id],
             where: "is_default",
             name: :product_collections_one_default_per_artist
           )
  end

  # Takes the column away again. The data moves of steps 3 and 4 stay:
  # they are harmless with the old code too.
  def down do
    drop index(:product_collections, [:artist_id],
           name: :product_collections_one_default_per_artist
         )

    alter table(:product_collections) do
      remove :is_default
    end
  end
end
