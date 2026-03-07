defmodule ArtsyNeighbor.Repo.Migrations.AddUserToArtistTable do
  use Ecto.Migration

  def change do
    alter table(:artists) do
      add :user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:artists, [:user_id])


  end
end
