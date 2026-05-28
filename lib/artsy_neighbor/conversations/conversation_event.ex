defmodule ArtsyNeighbor.Conversations.ConversationEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversation_events" do
    #field :actor_type, :string
    field :actor_type, Ecto.Enum, values: [:buyer, :vendor, :system]
    field :event_type, Ecto.Enum, values: [:message, :status_change]
    field :body, :string
    field :from_status, :string
    field :to_status, :string

    belongs_to :conversation, ArtsyNeighbor.Conversations.Conversation
    belongs_to :order,        ArtsyNeighbor.Orders.Order
    belongs_to :actor,        ArtsyNeighbor.Accounts.User, foreign_key: :actor_id

    timestamps(updated_at: false, type: :utc_datetime)
  end

  def message_changeset(event, attrs) do
    event
    |> cast(attrs, [:actor_type, :body, :conversation_id, :actor_id])
    |> validate_required([:actor_type, :body, :conversation_id])
    |> validate_length(:body, min: 1, max: 2000)
  end

  def status_change_changeset(event, attrs) do
    event
    |> cast(attrs, [:actor_type, :from_status, :to_status, :conversation_id, :order_id, :actor_id])
    |> validate_required([:actor_type, :to_status, :conversation_id])
  end
end
