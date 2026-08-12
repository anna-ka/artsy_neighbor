defmodule ArtsyNeighbor.Repo.Migrations.ChangeBioToTextOnArtists do
  use Ecto.Migration

  def change do
    alter table(:artists) do
      modify :bio, :text
    end
  end
end
