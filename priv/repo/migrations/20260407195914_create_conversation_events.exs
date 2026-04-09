defmodule ArtsyNeighbor.Repo.Migrations.CreateConversationEvents do
  use Ecto.Migration

  def change do
    create table(:conversation_events) do
      add :actor_type, :string, null: false
      add :event_type, :string, null: false
      add :body, :text
      add :from_status, :string
      add :to_status, :string
      add :conversation_id, references(:conversations, on_delete: :nothing), null: false
      add :order_id, references(:orders, on_delete: :nothing)
      add :actor_id, references(:users, on_delete: :nothing)

      timestamps(updated_at: false, type: :utc_datetime)
    end


    create index(:conversation_events, [:order_id])
    create index(:conversation_events, [:actor_id])
    create index(:conversation_events, [:conversation_id, :inserted_at])

  end
end
