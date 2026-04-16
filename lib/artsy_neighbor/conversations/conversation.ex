defmodule ArtsyNeighbor.Conversations.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversations" do
    # When the last message or system event was posted — used to detect unread.
    field :last_event_at,      :utc_datetime

    # When each party last opened this conversation.
    # nil = never opened = always treated as unread.
    field :buyer_last_read_at,  :utc_datetime
    field :vendor_last_read_at, :utc_datetime

    belongs_to :artist, ArtsyNeighbor.Artists.Artist, foreign_key: :artist_id
    belongs_to :buyer, ArtsyNeighbor.Accounts.User, foreign_key: :buyer_id
    has_many :events, ArtsyNeighbor.Conversations.ConversationEvent
    has_many :orders, ArtsyNeighbor.Orders.Order

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:buyer_id, :artist_id])
    |> validate_required([:buyer_id, :artist_id])
  end
end
