defmodule ArtsyNeighbor.Repo.Migrations.AddSystemConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      # Distinguishes order conversations (buyer ↔ vendor) from system
      # conversations (platform → user). Existing rows default to "order".
      add :conversation_type, :string, default: "order", null: false

      # Owner of a system conversation. Null for order conversations.
      # Each user has at most one system conversation (enforced by the
      # unique index below).
      add :user_id, references(:users, on_delete: :delete_all)
    end

    create index(:conversations, [:user_id])

    # One system inbox per user — enforced at the database level with a
    # partial unique index so it only applies to system-type rows.
    create unique_index(
      :conversations,
      [:user_id],
      where: "conversation_type = 'system'",
      name: :conversations_system_user_unique
    )
  end
end
