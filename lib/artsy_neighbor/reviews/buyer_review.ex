defmodule ArtsyNeighbor.Reviews.BuyerReview do
  use Ecto.Schema
  import Ecto.Changeset

  schema "buyers_reviewed" do
    field :stars,        :integer
    field :body,         :string
    field :submitted_at, :utc_datetime

    belongs_to :order,    ArtsyNeighbor.Orders.Order
    belongs_to :reviewer, ArtsyNeighbor.Accounts.User, foreign_key: :reviewer_id
    belongs_to :buyer,    ArtsyNeighbor.Accounts.User, foreign_key: :buyer_id

    timestamps(type: :utc_datetime)
  end

  def changeset(review, attrs) do
    review
    |> cast(attrs, [:stars, :body, :order_id, :reviewer_id, :buyer_id, :submitted_at])
    |> validate_required([:stars, :order_id, :reviewer_id, :buyer_id])
    |> validate_inclusion(:stars, 1..5, message: "must be between 1 and 5")
    |> validate_length(:body, max: 500)
    |> unique_constraint(:order_id, message: "you have already reviewed this order")
  end
end
