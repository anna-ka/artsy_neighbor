defmodule ArtsyNeighbor.Repo.Migrations.AddIndexOnArtistsStatus do
  use Ecto.Migration

  # Products.only_available/1 (used by every public product listing/search/
  # detail query — filter_products/1, list_products_with_associations/0,
  # get_product_with_associations/1, get_products_by_artist/1,
  # get_products_by_category/1) now filters on artists.status via a
  # subquery on every call, added the same day as this migration. Without
  # an index, that subquery is a full sequential scan of the artists table
  # on every public product request.
  def change do
    create index(:artists, [:status])
  end
end
