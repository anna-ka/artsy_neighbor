defmodule ArtsyNeighbor.Repo.Migrations.AddStatusToConversationEvents do
  use Ecto.Migration

  def change do
    alter table(:conversation_events) do
      add :status, :string, default: "active", null: false
    end
  end
end
