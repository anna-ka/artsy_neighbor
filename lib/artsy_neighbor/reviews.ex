defmodule ArtsyNeighbor.Reviews do
  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo

  alias ArtsyNeighbor.Reviews.VendorReview
  alias ArtsyNeighbor.Reviews.BuyerReview
  alias ArtsyNeighbor.Reviews.ProductReview
  alias ArtsyNeighbor.Reviews.Flag

  @review_window_days 14
  @edit_window_days   30

  # ---------------------------------------------------------------------------
  # Create
  # ---------------------------------------------------------------------------

  def create_vendor_review(attrs) do
    %VendorReview{}
    |> VendorReview.changeset(Map.put(attrs, :submitted_at, DateTime.utc_now() |> DateTime.truncate(:second)))
    |> Repo.insert()
  end

  def create_buyer_review(attrs) do
    %BuyerReview{}
    |> BuyerReview.changeset(Map.put(attrs, :submitted_at, DateTime.utc_now() |> DateTime.truncate(:second)))
    |> Repo.insert()
  end

  def create_product_review(attrs) do
    %ProductReview{}
    |> ProductReview.changeset(Map.put(attrs, :submitted_at, DateTime.utc_now() |> DateTime.truncate(:second)))
    |> Repo.insert()
  end

  def create_flag(attrs) do
    %Flag{}
    |> Flag.changeset(attrs)
    |> Repo.insert()
  end

  # ---------------------------------------------------------------------------
  # Read — reviews per order
  # ---------------------------------------------------------------------------

  def get_vendor_review_for_order(order_id) do
    Repo.get_by(VendorReview, order_id: order_id)
  end

  def get_buyer_review_for_order(order_id) do
    Repo.get_by(BuyerReview, order_id: order_id)
  end

  def get_product_reviews_for_order(order_id) do
    ProductReview
    |> where(order_id: ^order_id)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Read — visible reviews for public display
  #
  # A review is visible if both parties have submitted, OR the 14-day window
  # has expired since order completion. Visibility is computed on read so no
  # background job is needed.
  # ---------------------------------------------------------------------------

  def list_vendor_reviews_for_artist(artist_id) do
    now = DateTime.utc_now()
    window_cutoff = DateTime.add(now, -@review_window_days, :day)

    from(vr in VendorReview,
      join: br in BuyerReview, on: br.order_id == vr.order_id,
      join: o in ArtsyNeighbor.Orders.Order, on: o.id == vr.order_id,
      where: vr.artist_id == ^artist_id,
      where: not is_nil(br.id) or o.completed_at <= ^window_cutoff,
      order_by: [desc: vr.submitted_at]
    )
    |> Repo.all()
  end

  def list_buyer_reviews_for_user(buyer_id) do
    now = DateTime.utc_now()
    window_cutoff = DateTime.add(now, -@review_window_days, :day)

    from(br in BuyerReview,
      join: vr in VendorReview, on: vr.order_id == br.order_id,
      join: o in ArtsyNeighbor.Orders.Order, on: o.id == br.order_id,
      where: br.buyer_id == ^buyer_id,
      where: not is_nil(vr.id) or o.completed_at <= ^window_cutoff,
      order_by: [desc: br.submitted_at]
    )
    |> Repo.all()
  end

  def list_product_reviews_for_product(product_id) do
    now = DateTime.utc_now()
    window_cutoff = DateTime.add(now, -@review_window_days, :day)

    from(pr in ProductReview,
      join: o in ArtsyNeighbor.Orders.Order, on: o.id == pr.order_id,
      join: vr in VendorReview, on: vr.order_id == pr.order_id,
      join: br in BuyerReview, on: br.order_id == pr.order_id,
      where: pr.product_id == ^product_id,
      where: (not is_nil(vr.id) and not is_nil(br.id)) or o.completed_at <= ^window_cutoff,
      order_by: [desc: pr.submitted_at]
    )
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Aggregation — average star ratings
  # ---------------------------------------------------------------------------

  def avg_rating_for_artist(artist_id) do
    now = DateTime.utc_now()
    window_cutoff = DateTime.add(now, -@review_window_days, :day)

    from(vr in VendorReview,
      join: br in BuyerReview, on: br.order_id == vr.order_id,
      join: o in ArtsyNeighbor.Orders.Order, on: o.id == vr.order_id,
      where: vr.artist_id == ^artist_id,
      where: not is_nil(br.id) or o.completed_at <= ^window_cutoff,
      select: avg(vr.stars)
    )
    |> Repo.one()
    |> then(fn avg -> if avg, do: Float.round(avg / 1, 1), else: nil end)
  end

  def avg_rating_for_buyer(buyer_id) do
    now = DateTime.utc_now()
    window_cutoff = DateTime.add(now, -@review_window_days, :day)

    from(br in BuyerReview,
      join: vr in VendorReview, on: vr.order_id == br.order_id,
      join: o in ArtsyNeighbor.Orders.Order, on: o.id == br.order_id,
      where: br.buyer_id == ^buyer_id,
      where: not is_nil(vr.id) or o.completed_at <= ^window_cutoff,
      select: avg(br.stars)
    )
    |> Repo.one()
    |> then(fn avg -> if avg, do: Float.round(avg / 1, 1), else: nil end)
  end

  def avg_rating_for_product(product_id) do
    now = DateTime.utc_now()
    window_cutoff = DateTime.add(now, -@review_window_days, :day)

    from(pr in ProductReview,
      join: o in ArtsyNeighbor.Orders.Order, on: o.id == pr.order_id,
      join: vr in VendorReview, on: vr.order_id == pr.order_id,
      join: br in BuyerReview, on: br.order_id == pr.order_id,
      where: pr.product_id == ^product_id,
      where: (not is_nil(vr.id) and not is_nil(br.id)) or o.completed_at <= ^window_cutoff,
      select: avg(pr.stars)
    )
    |> Repo.one()
    |> then(fn avg -> if avg, do: Float.round(avg / 1, 1), else: nil end)
  end

  # ---------------------------------------------------------------------------
  # Read — flags (admin)
  # ---------------------------------------------------------------------------

  def list_flags(filters \\ %{}) do
    Flag
    |> filter_flags_by_status(filters["status"])
    |> filter_flags_by_subject_type(filters["subject_type"])
    |> filter_flags_by_reporter(filters["reporter_id"])
    |> order_by([f], asc: f.inserted_at)
    |> Repo.all()
  end

  def get_flags_for(subject_type, subject_id) do
    Flag
    |> where(subject_type: ^subject_type, subject_id: ^subject_id)
    |> order_by([f], asc: f.inserted_at)
    |> Repo.all()
  end

  def pending_flag_count do
    Flag
    |> where(status: :pending)
    |> Repo.aggregate(:count, :id)
  end

  defp filter_flags_by_status(query, nil), do: query
  defp filter_flags_by_status(query, status), do: where(query, [f], f.status == ^status)

  defp filter_flags_by_subject_type(query, nil), do: query
  defp filter_flags_by_subject_type(query, type), do: where(query, [f], f.subject_type == ^type)

  defp filter_flags_by_reporter(query, nil), do: query
  defp filter_flags_by_reporter(query, id), do: where(query, [f], f.reporter_id == ^id)

  # ---------------------------------------------------------------------------
  # Nav badge — pending review counts
  # ---------------------------------------------------------------------------

  def pending_reviews_of_vendor_count(user_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@review_window_days, :day)

    from(o in ArtsyNeighbor.Orders.Order,
      left_join: vr in VendorReview, on: vr.order_id == o.id,
      where: o.buyer_id == ^user_id,
      where: o.status == :completed,
      where: not is_nil(o.completed_at),
      where: o.completed_at >= ^cutoff,
      where: is_nil(vr.id),
      select: count(o.id)
    )
    |> Repo.one()
  end

  def pending_reviews_of_buyer_count(user_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@review_window_days, :day)

    from(o in ArtsyNeighbor.Orders.Order,
      join: a in ArtsyNeighbor.Artists.Artist, on: a.id == o.artist_id,
      left_join: br in BuyerReview, on: br.order_id == o.id,
      where: a.user_id == ^user_id,
      where: o.status == :completed,
      where: not is_nil(o.completed_at),
      where: o.completed_at >= ^cutoff,
      where: is_nil(br.id),
      select: count(o.id)
    )
    |> Repo.one()
  end

  # Returns a MapSet of order IDs where the buyer has already submitted a
  # vendor review — used to drive the "Reviewed / Pending" pill on order rows.
  def reviewed_order_ids_as_buyer(user_id) do
    from(r in VendorReview, where: r.reviewer_id == ^user_id, select: r.order_id)
    |> Repo.all()
    |> MapSet.new()
  end

  # Returns a MapSet of order IDs where the vendor has already submitted a
  # buyer review — used to drive the "Reviewed / Pending" pill on sales rows.
  def reviewed_order_ids_as_vendor(user_id) do
    from(r in BuyerReview, where: r.reviewer_id == ^user_id, select: r.order_id)
    |> Repo.all()
    |> MapSet.new()
  end

  def order_in_review_window?(%{completed_at: nil}), do: false
  def order_in_review_window?(%{completed_at: completed_at}) do
    DateTime.diff(DateTime.utc_now(), completed_at, :day) < @review_window_days
  end

  # ---------------------------------------------------------------------------
  # Update — within 30-day edit window
  # ---------------------------------------------------------------------------

  def update_vendor_review(%VendorReview{} = review, attrs) do
    if within_edit_window?(review) do
      review |> VendorReview.changeset(attrs) |> Repo.update()
    else
      {:error, :edit_window_expired}
    end
  end

  def update_buyer_review(%BuyerReview{} = review, attrs) do
    if within_edit_window?(review) do
      review |> BuyerReview.changeset(attrs) |> Repo.update()
    else
      {:error, :edit_window_expired}
    end
  end

  def update_product_review(%ProductReview{} = review, attrs) do
    if within_edit_window?(review) do
      review |> ProductReview.changeset(attrs) |> Repo.update()
    else
      {:error, :edit_window_expired}
    end
  end

  # ---------------------------------------------------------------------------
  # Delete
  # ---------------------------------------------------------------------------

  def delete_vendor_review(%VendorReview{} = review, opts \\ []) do
    if opts[:admin] || within_edit_window?(review) do
      Repo.delete(review)
    else
      {:error, :edit_window_expired}
    end
  end

  def delete_buyer_review(%BuyerReview{} = review, opts \\ []) do
    if opts[:admin] || within_edit_window?(review) do
      Repo.delete(review)
    else
      {:error, :edit_window_expired}
    end
  end

  def delete_product_review(%ProductReview{} = review, opts \\ []) do
    if opts[:admin] || within_edit_window?(review) do
      Repo.delete(review)
    else
      {:error, :edit_window_expired}
    end
  end

  # ---------------------------------------------------------------------------
  # Flag resolution (admin)
  # ---------------------------------------------------------------------------

  def resolve_flag(%Flag{} = flag, admin_user_id) do
    flag
    |> Flag.resolution_changeset(%{
      status: :reviewed,
      reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      reviewed_by: admin_user_id
    })
    |> Repo.update()
  end

  def dismiss_flag(%Flag{} = flag, admin_user_id) do
    flag
    |> Flag.resolution_changeset(%{
      status: :dismissed,
      reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      reviewed_by: admin_user_id
    })
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Visibility and window helpers
  # ---------------------------------------------------------------------------

  def review_visible?(vendor_review, buyer_review, order) do
    both_submitted = not is_nil(vendor_review) and not is_nil(buyer_review)
    window_expired = window_expired?(order)
    both_submitted or window_expired
  end

  def edit_window_days, do: @edit_window_days

  def within_edit_window?(review) do
    DateTime.diff(DateTime.utc_now(), review.submitted_at, :day) <= @edit_window_days
  end

  def days_remaining_in_window(order) do
    if is_nil(order.completed_at) do
      0
    else
      elapsed = DateTime.diff(DateTime.utc_now(), order.completed_at, :day)
      max(@review_window_days - elapsed, 0)
    end
  end

  # Returns the review status from the perspective of current_user.
  # Used to drive the status pill on the order history page.
  def review_status_for_order(order, vendor_review, buyer_review, current_user_id, role) do
    expired = window_expired?(order)

    my_review    = if role == :buyer, do: vendor_review, else: buyer_review
    other_review = if role == :buyer, do: buyer_review,  else: vendor_review

    _ = current_user_id

    cond do
      not is_nil(my_review) and not is_nil(other_review) -> :complete
      not is_nil(my_review) and expired                  -> :published
      not is_nil(my_review)                              -> :waiting_other_party
      expired                                            -> :expired
      true                                               -> :pending_yours
    end
  end

  defp window_expired?(order) do
    not is_nil(order.completed_at) and
      DateTime.diff(DateTime.utc_now(), order.completed_at, :day) > @review_window_days
  end
end
