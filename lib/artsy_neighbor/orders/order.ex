defmodule ArtsyNeighbor.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  schema "orders" do
    field :status, Ecto.Enum,
      values: [:requested, :confirmed, :completed, :cancelled, :refunded],
      default: :requested
    field :delivery_method, Ecto.Enum, values: [:pickup, :delivery], default: :pickup
    field :delivery_address, :string
    field :subtotal, :decimal
    field :platform_fee, :decimal
    field :total, :decimal
    field :complete_token, :string
    field :complete_token_at, :utc_datetime

    field :buyer_email,  :string
    field :vendor_email, :string
    field :artist_name,  :string

    belongs_to :conversation, ArtsyNeighbor.Conversations.Conversation
    belongs_to :buyer, ArtsyNeighbor.Accounts.User, foreign_key: :buyer_id
    belongs_to :artist, ArtsyNeighbor.Artists.Artist, foreign_key: :artist_id

    has_many :items, ArtsyNeighbor.Orders.OrderItem
    has_many :events, ArtsyNeighbor.Conversations.ConversationEvent

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:status, :delivery_method, :delivery_address, :subtotal,
                    :platform_fee, :total, :complete_token, :complete_token_at,
                    :conversation_id, :buyer_id, :artist_id,
                    :buyer_email, :vendor_email, :artist_name])
    |> validate_required([:status, :delivery_method, :conversation_id, :buyer_id, :artist_id])
  end

end
