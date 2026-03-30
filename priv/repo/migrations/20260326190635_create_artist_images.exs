defmodule ArtsyNeighbor.Repo.Migrations.CreateArtistImages do
  use Ecto.Migration

  def change do
    create table(:artist_images) do
      add :path, :string
      add :position, :integer
      add :artist_id, references(:artists, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:artist_images, [:artist_id])
    create index(:artist_images, [:artist_id, :position])
  end
end
