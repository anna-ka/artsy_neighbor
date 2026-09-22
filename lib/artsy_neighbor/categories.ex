defmodule ArtsyNeighbor.Categories do
  @moduledoc """
  The Categories context.
  """

  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo

  alias ArtsyNeighbor.Categories.Category
  alias ArtsyNeighbor.Products.Product

  @doc """
  Returns the list of active categories.

  ## Examples

      iex> list_categories()
      [%Category{}, ...]

  """
  def list_categories do
    Category
    |> with_status(:active)
    |> Repo.all()
  end

  @doc """
  List of active categories ordered by insertion time.
  In practice, this means most important categories (those created first) will be listed first.
  """
  def list_categories_ordered_by_time do
    Category
    |> with_status(:active)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns every category regardless of status, for admin use. Sorted
  active before archived, then by name within each group.
  """
  def list_categories_all_status do
    Category
    |> order_by([c], fragment("CASE WHEN ? = 'active' THEN 0 ELSE 1 END", c.status))
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  @doc """
  Filters a Category query by the given status. If status is nil, returns
  the query unfiltered.
  """
  def with_status(query, nil), do: query
  def with_status(query, status), do: where(query, [c], c.status == ^status)

  @doc """
  Gets a single category, scoped to public visibility (status: :active).
  Returns nil if the category doesn't exist OR isn't currently active, so
  a direct hit on an archived category's URL 404s the same way a bad id
  does, instead of leaking the category page — the same class of leak
  Phase 0 fixed for ProductLive.Show. For the admin equivalent, see
  AdminCategories.get_category!/1, which is already unscoped.
  """
  def get_category(id) do
    Category
    |> with_status(:active)
    |> Repo.get(id)
  end

  @doc """
  Gets a single category by id, unscoped by status.

  Raises `Ecto.NoResultsError` if the Category does not exist.

  ## Examples

      iex> get_category!(123)
      %Category{}

      iex> get_category!(456)
      ** (Ecto.NoResultsError)

  """
  def get_category!(id), do: Repo.get!(Category, id)

  @doc """
  True if the category has any :available products still attached to it.
  Used as a removal guard by soft_delete_category/1 and
  AdminCategories.hard_delete_category/1 — a category still backing live,
  purchasable products can't be archived or permanently deleted out from
  under them. :unavailable and :archived products don't count: they're
  already hidden from the public regardless of their category's status.
  """
  def has_active_products?(%Category{} = category) do
    Repo.exists?(
      from(p in Product, where: p.category_id == ^category.id and p.status == :available)
    )
  end

  @doc """
  Marks a category as :archived. Categories are never hard-deleted under
  normal circumstances — see AdminCategories.hard_delete_category/1 for
  the rare, admin/testing-only exception.

  Refuses (returns {:error, :has_active_products}) if the category still
  has :available products — see has_active_products?/1.
  """
  def soft_delete_category(%Category{} = category) do
    if has_active_products?(category) do
      {:error, :has_active_products}
    else
      category
      |> Category.status_changeset(%{status: :archived})
      |> Repo.update()
    end
  end

  @doc """
  Reverses soft_delete_category/1, setting status back to :active.

  Refuses (returns {:error, :already_active}) if the category is
  currently :active — restoring is meant to bring an archived category
  back into view, not silently no-op on a live one while still reporting
  success.
  """
  def restore_category(%Category{status: :active}), do: {:error, :already_active}

  def restore_category(%Category{} = category) do
    category
    |> Category.status_changeset(%{status: :active})
    |> Repo.update()
  end
end
