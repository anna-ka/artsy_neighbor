defmodule ArtsyNeighbor.ReviewsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `ArtsyNeighbor.Reviews` context.
  """

  alias ArtsyNeighbor.Repo
  alias ArtsyNeighbor.Reviews

  def vendor_review_fixture(attrs \\ %{}) do
    {:ok, review} =
      attrs
      |> Enum.into(%{stars: 5, body: "Great vendor!"})
      |> Reviews.create_vendor_review()

    review
  end

  def buyer_review_fixture(attrs \\ %{}) do
    {:ok, review} =
      attrs
      |> Enum.into(%{stars: 5, body: "Great buyer!"})
      |> Reviews.create_buyer_review()

    review
  end

  def product_review_fixture(attrs \\ %{}) do
    {:ok, review} =
      attrs
      |> Enum.into(%{stars: 5, body: "Great product!"})
      |> Reviews.create_product_review()

    review
  end

  def flag_fixture(attrs \\ %{}) do
    {:ok, flag} =
      attrs
      |> Enum.into(%{
        subject_type: "vendor",
        reason: "This vendor never showed up for the scheduled pickup."
      })
      |> Reviews.create_flag()

    flag
  end

  @doc """
  Backdates submitted_at on a review, for testing edit-window expiry.
  """
  def backdate_submission(review, days_ago) do
    submitted_at =
      DateTime.utc_now()
      |> DateTime.add(-days_ago, :day)
      |> DateTime.truncate(:second)

    review
    |> Ecto.Changeset.change(submitted_at: submitted_at)
    |> Repo.update!()
  end
end
