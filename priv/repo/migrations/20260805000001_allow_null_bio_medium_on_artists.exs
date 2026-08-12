defmodule ArtsyNeighbor.Repo.Migrations.AllowNullBioMediumOnArtists do
  use Ecto.Migration

  def change do
    alter table(:artists) do
      modify :bio, :string, null: true
      modify :medium, {:array, :string}, null: true
    end
  end
end
