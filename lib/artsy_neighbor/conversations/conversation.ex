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

    # :active = visible to its participants. :archived = hidden/muted by an
    # admin (e.g. a spam or abusive thread) without destroying message
    # history a moderation review might need.
    field :status, Ecto.Enum, values: [:active, :archived], default: :active
    field :status_changed_at, :utc_datetime

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

  @doc """
  Changeset for status-only updates (e.g. Conversations.soft_delete_conversation/1,
  restore_conversation/1). Scoped to just :status so archiving/restoring a
  conversation never risks re-running the participant-required validations
  above against fields that aren't changing.
  """
  def status_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> maybe_set_status_changed_at()
  end

  defp maybe_set_status_changed_at(changeset) do
    if changed?(changeset, :status) do
      put_change(changeset, :status_changed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    else
      changeset
    end
  end
end
