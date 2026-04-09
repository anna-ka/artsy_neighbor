defmodule ArtsyNeighbor.Conversations.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversations" do
    field :last_event_at, :utc_datetime

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
