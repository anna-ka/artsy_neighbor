defmodule ArtsyNeighbor.Reviews.VendorReview do
  use Ecto.Schema
  import Ecto.Changeset

  schema "vendors_reviewed" do
    field :stars,        :integer
    field :body,         :string
    field :submitted_at, :utc_datetime
    field :status, Ecto.Enum, values: [:active, :removed], default: :active
    field :status_changed_at, :utc_datetime

    belongs_to :order,    ArtsyNeighbor.Orders.Order
    belongs_to :reviewer, ArtsyNeighbor.Accounts.User, foreign_key: :reviewer_id
    belongs_to :artist,   ArtsyNeighbor.Artists.Artist

    timestamps(type: :utc_datetime)
  end

  def changeset(review, attrs) do
    review
    |> cast(attrs, [:stars, :body, :order_id, :reviewer_id, :artist_id, :submitted_at])
    |> validate_required([:stars, :order_id, :reviewer_id, :artist_id])
    |> validate_inclusion(:stars, 1..5, message: "must be between 1 and 5")
    |> validate_length(:body, max: 500)
    |> unique_constraint(:order_id, message: "you have already reviewed this order")
  end

  @doc """
  Changeset for status-only updates (Reviews.soft_delete_vendor_review/2,
  the resubmit-revives-a-removed-row path in Reviews.create_vendor_review/1).
  Scoped to just :status so it never risks re-running the full validations
  above against fields that aren't changing.
  """
  def status_changeset(review, attrs) do
    review
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
