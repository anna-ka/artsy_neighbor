defmodule ArtsyNeighbor.Admin.AdminProducts do
  @moduledoc """
  Admin context module for products: the product writes in which the
  admin picks the owner (`artist_id`) from a form.

  A vendor's own form never uses these: there the owner is the logged-in
  artist, passed separately to `Products.create_product/2` (audit S-3).
  Everything else about products is in `ArtsyNeighbor.Products`.
  """

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.Product

  @doc """
  Creates a product with the artist the admin picked (`artist_id` in
  `attrs`). It starts as a draft, like every new product.
  """
  def create_product(attrs) do
    %Product{}
    |> change_product(attrs)
    |> Products.save_product()
  end

  @doc """
  Updates a product's fields and, if `attrs` says so, its owner. Never
  changes the status. A work moved to another artist without a new
  collection goes into that artist's default collection.
  """
  def update_product(%Product{} = product, attrs) do
    product
    |> change_product(attrs)
    |> Products.save_product()
  end

  @doc """
  A changeset for the admin product form. Unlike the vendor's form, it
  takes the owner (`artist_id`): see `Product.admin_changeset/2`.
  """
  def change_product(%Product{} = product, attrs \\ %{}) do
    product
    |> Product.admin_changeset(attrs)
    |> clear_old_collection()
  end

  # When a work moves to another artist and no other collection was
  # chosen, its old collection (the old artist's) can't stay: clear it,
  # so that saving puts the work in the new artist's default collection
  # (Products.save_product/1). Without this the save would be refused,
  # and the form's collection field may not even be sendable (it is
  # disabled while the new artist has no collections).
  defp clear_old_collection(changeset) do
    moved? = Ecto.Changeset.changed?(changeset, :artist_id)
    collection_chosen? = Ecto.Changeset.changed?(changeset, :collection_id)

    if moved? and not collection_chosen? do
      Ecto.Changeset.put_change(changeset, :collection_id, nil)
    else
      changeset
    end
  end
end
