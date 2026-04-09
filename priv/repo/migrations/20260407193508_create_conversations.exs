defmodule ArtsyNeighbor.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :last_event_at, :utc_datetime
      add :buyer_id, references(:users, on_delete: :nothing), null: false
      add :artist_id, references(:artists, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:conversations, [:buyer_id, :artist_id])
    create index(:conversations, [:buyer_id])
    create index(:conversations, [:artist_id])
  end
end
