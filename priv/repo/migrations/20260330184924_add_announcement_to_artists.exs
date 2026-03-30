defmodule ArtsyNeighbor.Repo.Migrations.AddAnnouncementToArtists do
  use Ecto.Migration

  def change do
    alter table(:artists) do
      add :announcement, :string
      add :announcement_active, :boolean, default: false, null: false
    end
  end
end
