defmodule ArtsyNeighbor.Conversations.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversations" do
    # :order — a standard buyer ↔ vendor thread tied to a purchase.
    # :system — a private platform → user inbox for notifications and
    #           admin messages. buyer_id and artist_id are nil; user_id is set.
    field :conversation_type, Ecto.Enum, values: [:order, :system], default: :order

    # When the last message or system event was posted — used to detect unread.
    field :last_event_at,      :utc_datetime

    # When each party last opened this conversation.
    # nil = never opened = always treated as unread.
    # For :system conversations, buyer_last_read_at doubles as the user's
    # read timestamp (there is no vendor side).
    field :buyer_last_read_at,  :utc_datetime
    field :vendor_last_read_at, :utc_datetime

    belongs_to :artist, ArtsyNeighbor.Artists.Artist, foreign_key: :artist_id
    belongs_to :buyer,  ArtsyNeighbor.Accounts.User,  foreign_key: :buyer_id

    # Owner of a :system conversation. Nil for :order conversations.
    belongs_to :user, ArtsyNeighbor.Accounts.User, foreign_key: :user_id

    has_many :events, ArtsyNeighbor.Conversations.ConversationEvent
    has_many :orders, ArtsyNeighbor.Orders.Order

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for a standard buyer ↔ vendor order conversation."
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:buyer_id, :artist_id])
    |> validate_required([:buyer_id, :artist_id])
  end

  @doc """
  Changeset for a system (platform → user) conversation.
  Sets conversation_type to :system and validates that user_id is present.
  The unique DB index guarantees at most one system conversation per user.
  """
  def system_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:user_id])
    |> validate_required([:user_id])
    |> put_change(:conversation_type, :system)
    |> unique_constraint(:user_id, name: :conversations_system_user_unique,
         message: "already has a system conversation")
  end
end
