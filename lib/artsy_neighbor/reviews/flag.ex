defmodule ArtsyNeighbor.Reviews.Flag do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_subject_types ~w(vendor buyer vendor_review_of buyer_review_of product_review_of)

  schema "flags" do
    field :subject_type, :string
    field :subject_id,   :integer
    field :reason,       :string
    field :status,       Ecto.Enum, values: [:pending, :reviewed, :dismissed], default: :pending
    field :reviewed_at,  :utc_datetime

    belongs_to :reporter,     ArtsyNeighbor.Accounts.User, foreign_key: :reporter_id
    belongs_to :resolved_by,  ArtsyNeighbor.Accounts.User, foreign_key: :reviewed_by

    timestamps(type: :utc_datetime)
  end

  def changeset(flag, attrs) do
    flag
    |> cast(attrs, [:subject_type, :subject_id, :reason, :reporter_id])
    |> validate_required([:subject_type, :subject_id, :reason, :reporter_id])
    |> validate_inclusion(:subject_type, @valid_subject_types,
        message: "must be one of: #{Enum.join(@valid_subject_types, ", ")}")
    |> validate_length(:reason, min: 20, max: 1000,
        message: "please describe your concern in at least 20 characters")
    |> unique_constraint([:reporter_id, :subject_type, :subject_id],
        message: "you have already flagged this")
  end

  def resolution_changeset(flag, attrs) do
    flag
    |> cast(attrs, [:status, :reviewed_at, :reviewed_by])
    |> validate_required([:status, :reviewed_at, :reviewed_by])
  end
end
