defmodule ArtsyNeighbor.Conversations.ConversationEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversation_events" do
    # field :actor_type, :string
    field :actor_type, Ecto.Enum, values: [:buyer, :vendor, :system]
    field :event_type, Ecto.Enum, values: [:message, :status_change]
    field :body, :string
    field :from_status, :string
    field :to_status, :string

    # The event's own visibility state — distinct from from_status/to_status
    # above, which record an *order's* status for :status_change events.
    # :active = visible normally. :deleted = its sender removed it; the
    # thread still renders a "message deleted" placeholder in its place so a
    # reply pointing at it doesn't lose context. Only event_type: :message
    # rows are ever :deleted — :status_change events are the order's audit
    # trail and are never deletable.
    field :status, Ecto.Enum, values: [:active, :deleted], default: :active

    belongs_to :conversation, ArtsyNeighbor.Conversations.Conversation
    belongs_to :order, ArtsyNeighbor.Orders.Order
    belongs_to :actor, ArtsyNeighbor.Accounts.User, foreign_key: :actor_id

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
    |> cast(attrs, [
      :actor_type,
      :body,
      :from_status,
      :to_status,
      :conversation_id,
      :order_id,
      :actor_id
    ])
    |> validate_required([:actor_type, :to_status, :conversation_id])
  end

  @doc """
  Changeset for soft-deleting a message (status -> :deleted). See
  Conversations.soft_delete_event/2.
  """
  def delete_changeset(event, attrs) do
    event
    |> cast(attrs, [:status])
    |> validate_required([:status])
  end
end
