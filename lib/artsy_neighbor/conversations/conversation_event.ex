defmodule ArtsyNeighbor.Conversations.ConversationEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversation_events" do
    #field :actor_type, :string
    field :actor_type, Ecto.Enum, values: [:buyer, :vendor, :system]
    field :event_type, :string
    field :body, :string
    field :from_status, :string
    field :to_status, :string

    belongs_to :conversation, ArtsyNeighbor.Conversations.Conversation
    belongs_to :order,        ArtsyNeighbor.Orders.Order
    belongs_to :actor,        ArtsyNeighbor.Accounts.User, foreign_key: :actor_id

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc false
  def changeset(conversation_event, attrs) do
    conversation_event
    |> cast(attrs, [:actor_type, :event_type, :body, :from_status, :to_status,
                  :conversation_id, :order_id, :actor_id])
    |> validate_required([:actor_type, :event_type, :conversation_id, :body])
    |> validate_length(:body, min: 1, max: 2000)
  end
end
