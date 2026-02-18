defmodule ArtsyNeighbor.Categories.Category do
  use Ecto.Schema
  import Ecto.Changeset

  schema "categories" do
    field :name, :string
    field :description, :string
    field :main_img, :string, default: "/images/placeholder-category.jpg"
    field :slug, :string

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
        message: "can only contain lowercase letters, numbers, and hyphens (no leading/trailing/consecutive hyphens)")
    |> unique_constraint(:slug)
    |> unique_constraint(:name)
  end
end
