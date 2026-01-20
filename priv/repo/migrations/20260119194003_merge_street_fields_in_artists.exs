defmodule ArtsyNeighbor.Repo.Migrations.MergeStreetFieldsInArtists do
  use Ecto.Migration

  def change do
    alter table(:artists) do
      add :street_address, :string, null: false
      remove :street
      remove :street_number
    end
  end
end
