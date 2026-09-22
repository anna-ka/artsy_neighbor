defmodule ArtsyNeighbor.Categories.Category do
  use Ecto.Schema
  import Ecto.Changeset

  schema "categories" do
    field :name, :string
    field :description, :string
    field :main_img, :string, default: "/images/placeholder-category.jpg"
    field :slug, :string
    field :status, Ecto.Enum, values: [:active, :archived], default: :active
    field :status_changed_at, :utc_datetime

    has_many :products, ArtsyNeighbor.Products.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description, :main_img, :slug])
    |> validate_required([:name, :description, :slug])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, min: 10, max: 1000)
    |> validate_length(:slug, min: 1, max: 50)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
        message: "A slug can only contain lowercase letters, numbers, and hyphens (no leading/trailing/consecutive hyphens)")
    |> unique_constraint(:slug)
    |> unique_constraint(:name)
  end

  @doc """
  Changeset for status-only updates (e.g. Categories.soft_delete_category/1,
  restore_category/1). Scoped to just :status so archiving/restoring a
  category never risks re-running the full-profile validations above
  against fields that aren't changing.
  """
  def status_changeset(category, attrs) do
    category
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> maybe_set_status_changed_at()
  end

  defp maybe_set_status_changed_at(changeset) do
    if changed?(changeset, :status) do
      put_change(changeset, :status_changed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    else
      changeset
    end
  end
end
