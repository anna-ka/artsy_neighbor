defmodule ArtsyNeighbor.Admin.AdminCategories do

  @moduledoc """
  Admin context module for managing categories of products.
  """


  alias ArtsyNeighbor.Repo
  alias ArtsyNeighbor.Categories
  alias ArtsyNeighbor.Categories.Category

  import Ecto.Query, warn: false


  @doc """
  Returns every category regardless of status, for admin use. See
  Categories.list_categories_all_status/0.
  """
  def list_categories_all_status do
    Categories.list_categories_all_status()
  end

  @doc """
  Gets a single category.

  Raises `Ecto.NoResultsError` if the Category does not exist.

  ## Examples

      iex> get_category!(123)
      %Category{}

      iex> get_category!(456)
      ** (Ecto.NoResultsError)

  """
  def get_category!(id), do: Repo.get!(Category, id)

  @doc """
  Creates a category.

  ## Examples

      iex> create_category(%{field: value})
      {:ok, %Category{}}

      iex> create_category(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_category(attrs) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a category.

  ## Examples

      iex> update_category(category, %{field: new_value})
      {:ok, %Category{}}

      iex> update_category(category, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Permanently deletes a category. Kept as the demoted, exceptional
  action — for routine removal use Categories.soft_delete_category/1
  instead, which is reversible. Stays a bare Repo.delete: products.category_id
  is on_delete: :nilify_all, and Category is never a Flag.subject_type, so
  this doesn't need the Multi+rescue+flag-cleanup treatment
  hard_delete_artist/1 and hard_delete_product/1 require.

  Refuses (returns {:error, :has_active_products}) if the category still
  has :available products, same guard and criteria as
  Categories.soft_delete_category/1 — an irreversible delete shouldn't be
  any more permissive than the reversible one.

  ## Examples

      iex> hard_delete_category(category)
      {:ok, %Category{}}

      iex> hard_delete_category(category)
      {:error, %Ecto.Changeset{}}

  """
  def hard_delete_category(%Category{} = category) do
    if Categories.has_active_products?(category) do
      {:error, :has_active_products}
    else
      Repo.delete(category)
    end
  end

  @doc """
  Marks a category as removed (soft, reversible). See
  Categories.soft_delete_category/1.
  """
  def soft_delete_category(%Category{} = category) do
    Categories.soft_delete_category(category)
  end

  @doc """
  Reverses soft_delete_category/1. See Categories.restore_category/1.
  """
  def restore_category(%Category{} = category) do
    Categories.restore_category(category)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.

  ## Examples

      iex> change_category(category)
      %Ecto.Changeset{data: %Category{}}

  """
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end


end
