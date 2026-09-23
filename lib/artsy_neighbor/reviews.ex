defmodule ArtsyNeighbor.Reviews do
  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo
  alias Ecto.Multi

  alias ArtsyNeighbor.Reviews.VendorReview
  alias ArtsyNeighbor.Reviews.BuyerReview
  alias ArtsyNeighbor.Reviews.ProductReview
  alias ArtsyNeighbor.Reviews.Flag

  @review_window_days 14
  @edit_window_days 30

  # ---------------------------------------------------------------------------
  # Create
  # ---------------------------------------------------------------------------

  @doc """
  Creates a vendor review — or, if the buyer previously soft-deleted their
  review of this order (status: :removed), revives that row instead of
  inserting a new one. Reviving in place (rather than inserting) is required
  because the row still occupies the order's unique_constraint(:order_id)
  slot; it also preserves the flag-cleanup/history tie to the original row.
  """
  def create_vendor_review(attrs) do
    lookup = [order_id: Map.get(attrs, :order_id)]
    create_or_revive_review(VendorReview, lookup, attrs)
  end

  @doc """
  Creates a buyer review — or revives a previously soft-deleted one for this
  order. See create_vendor_review/1 for why revive-in-place is necessary.
  """
  def create_buyer_review(attrs) do
    lookup = [order_id: Map.get(attrs, :order_id)]
    create_or_revive_review(BuyerReview, lookup, attrs)
  end

  @doc """
  Creates a product review — or revives a previously soft-deleted one for
  this order+product pair. See create_vendor_review/1 for why revive-in-place
  is necessary.
  """
  def create_product_review(attrs) do
    lookup = [order_id: Map.get(attrs, :order_id), product_id: Map.get(attrs, :product_id)]
    create_or_revive_review(ProductReview, lookup, attrs)
  end

  # Shared by create_vendor_review/1, create_buyer_review/1, and
  # create_product_review/1.
  #
  # `lookup` is a keyword list of the field(s) that uniquely identify "the
  # same review" for this schema — just order_id for a vendor/buyer review,
  # or order_id + product_id for a product review (one order can have
  # several product reviews). Each caller above builds its own `lookup`, so
  # this function doesn't need to know which fields matter for which schema.
  #
  # We use `lookup` to search for a previously soft-deleted row (status:
  # :removed) with those same values. If one exists, we update it back to
  # :active with the new content instead of inserting a fresh row — the old
  # row still occupies that unique slot in the database, so a plain insert
  # would fail.
  defp create_or_revive_review(schema, lookup, attrs) do
    attrs = Map.put(attrs, :submitted_at, DateTime.utc_now() |> DateTime.truncate(:second))

    lookup_is_complete? =
      Enum.all?(lookup, fn {_field, value} -> not is_nil(value) end)

    removed_review =
      if lookup_is_complete? do
        Repo.get_by(schema, lookup ++ [status: :removed])
      else
        # A required field (e.g. order_id) is missing from attrs. Skip the
        # lookup — Ecto doesn't allow nil in a query like this — and let the
        # insert below fail normally with an ordinary changeset error instead.
        nil
      end

    if removed_review do
      revive_review(removed_review, schema, attrs)
    else
      # struct(schema) builds an empty struct for whichever module was
      # passed in — the same as writing %VendorReview{} directly, just
      # using a variable since this function doesn't know which schema it
      # is until it runs.
      new_review = struct(schema)
      changeset = schema.changeset(new_review, attrs)
      Repo.insert(changeset)
    end
  end

  # Applies the normal content changeset (new stars/body/submitted_at) plus
  # bringing status back to :active, in one update. Bypasses status_changeset/2
  # (which only ever touches :status) since this needs both content and status
  # in a single write.
  defp revive_review(review, schema, attrs) do
    review
    |> schema.changeset(attrs)
    |> Ecto.Changeset.put_change(:status, :active)
    |> Ecto.Changeset.put_change(
      :status_changed_at,
      DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update()
  end

  def create_flag(attrs) do
    %Flag{}
    |> Flag.changeset(attrs)
    |> Repo.insert()
  end

  # ---------------------------------------------------------------------------
  # Read — reviews per order
  # ---------------------------------------------------------------------------

  # Scoped to status: :active — a soft-deleted review reads as "no review
  # yet" (so the review form's create-vs-edit check offers a fresh form,
  # which create_vendor_review/1 then revives in place) rather than
  # resurfacing removed content.
  def get_vendor_review_for_order(order_id) do
    Repo.get_by(VendorReview, order_id: order_id, status: :active)
  end

  def get_buyer_review_for_order(order_id) do
    Repo.get_by(BuyerReview, order_id: order_id, status: :active)
  end

  def get_product_reviews_for_order(order_id) do
    ProductReview
    |> where(order_id: ^order_id, status: :active)
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
      left_join: br in BuyerReview,
      on: br.order_id == vr.order_id and br.status == :active,
      join: o in ArtsyNeighbor.Orders.Order,
      on: o.id == vr.order_id,
      where: vr.artist_id == ^artist_id,
      where: vr.status == :active,
      where: not is_nil(br.id) or o.completed_at <= ^window_cutoff,
      order_by: [desc: vr.submitted_at]
    )
    |> Repo.all()
  end

  def list_buyer_reviews_for_user(buyer_id) do
    now = DateTime.utc_now()
    window_cutoff = DateTime.add(now, -@review_window_days, :day)

    from(br in BuyerReview,
      left_join: vr in VendorReview,
      on: vr.order_id == br.order_id and vr.status == :active,
      join: o in ArtsyNeighbor.Orders.Order,
      on: o.id == br.order_id,
      where: br.buyer_id == ^buyer_id,
      where: br.status == :active,
      where: not is_nil(vr.id) or o.completed_at <= ^window_cutoff,
      order_by: [desc: br.submitted_at]
    )
    |> Repo.all()
  end

  def list_product_reviews_for_product(product_id) do
    now = DateTime.utc_now()
    window_cutoff = DateTime.add(now, -@review_window_days, :day)

    from(pr in ProductReview,
      join: o in ArtsyNeighbor.Orders.Order,
      on: o.id == pr.order_id,
      left_join: vr in VendorReview,
      on: vr.order_id == pr.order_id and vr.status == :active,
      left_join: br in BuyerReview,
      on: br.order_id == pr.order_id and br.status == :active,
      where: pr.product_id == ^product_id,
      where: pr.status == :active,
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
      left_join: br in BuyerReview,
      on: br.order_id == vr.order_id and br.status == :active,
      join: o in ArtsyNeighbor.Orders.Order,
      on: o.id == vr.order_id,
      where: vr.artist_id == ^artist_id,
      where: vr.status == :active,
      where: not is_nil(br.id) or o.completed_at <= ^window_cutoff,
      select: avg(vr.stars)
    )
    |> Repo.one()
    |> then(fn avg -> if avg, do: avg |> Decimal.to_float() |> Float.round(1), else: nil end)
  end

  def avg_rating_for_buyer(buyer_id) do
    now = DateTime.utc_now()
    window_cutoff = DateTime.add(now, -@review_window_days, :day)

    from(br in BuyerReview,
      left_join: vr in VendorReview,
      on: vr.order_id == br.order_id and vr.status == :active,
      join: o in ArtsyNeighbor.Orders.Order,
      on: o.id == br.order_id,
      where: br.buyer_id == ^buyer_id,
      where: br.status == :active,
      where: not is_nil(vr.id) or o.completed_at <= ^window_cutoff,
      select: avg(br.stars)
    )
    |> Repo.one()
    |> then(fn avg -> if avg, do: avg |> Decimal.to_float() |> Float.round(1), else: nil end)
  end

  def avg_rating_for_product(product_id) do
    now = DateTime.utc_now()
    window_cutoff = DateTime.add(now, -@review_window_days, :day)

    from(pr in ProductReview,
      join: o in ArtsyNeighbor.Orders.Order,
      on: o.id == pr.order_id,
      left_join: vr in VendorReview,
      on: vr.order_id == pr.order_id and vr.status == :active,
      left_join: br in BuyerReview,
      on: br.order_id == pr.order_id and br.status == :active,
      where: pr.product_id == ^product_id,
      where: pr.status == :active,
      where: (not is_nil(vr.id) and not is_nil(br.id)) or o.completed_at <= ^window_cutoff,
      select: avg(pr.stars)
    )
    |> Repo.one()
    |> then(fn avg -> if avg, do: avg |> Decimal.to_float() |> Float.round(1), else: nil end)
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
  # Read — flags (reporting)
  # ---------------------------------------------------------------------------

  @doc """
  Resolves a subject_type + subject_id pair (as passed on the URL to
  FlagLive.New) into the real record being reported, so the reporting flow
  can confirm it exists and show what/who it is before the reporter
  submits.

  Handles all six subject types Flag itself allows, for consistency, even
  though — as of this writing — nothing in the UI actually links to
  flagging a review yet (reviews aren't shown publicly anywhere; only the
  two parties on an order ever see one, on their own private order pages).
  Wiring up entry-point links for "vendor_review_of"/"buyer_review_of"/
  "product_review_of" is deferred to a future UI pass, alongside a public
  reviews display and admin flag moderation — see CLAUDE.md.

  Does not filter by status/availability: a report is often about
  something that's already gone inactive/archived, and existence is the
  only requirement.
  """
  def resolve_subject("vendor", id) do
    with {:ok, id} <- parse_id(id),
         %ArtsyNeighbor.Artists.Artist{} = artist <- Repo.get(ArtsyNeighbor.Artists.Artist, id) do
      {:ok,
       %{
         type: "vendor",
         record: artist,
         display_name: artist.nickname,
         owner_user_id: artist.user_id
       }}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :invalid_id}
    end
  end

  def resolve_subject("buyer", id) do
    with {:ok, id} <- parse_id(id),
         %ArtsyNeighbor.Accounts.User{} = user <- Repo.get(ArtsyNeighbor.Accounts.User, id) do
      {:ok, %{type: "buyer", record: user, display_name: user.email, owner_user_id: user.id}}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :invalid_id}
    end
  end

  def resolve_subject("product", id) do
    with {:ok, id} <- parse_id(id),
         %ArtsyNeighbor.Products.Product{} = product <-
           Repo.get(ArtsyNeighbor.Products.Product, id) |> Repo.preload(:artist) do
      owner_user_id = product.artist && product.artist.user_id

      {:ok,
       %{
         type: "product",
         record: product,
         display_name: product.title,
         owner_user_id: owner_user_id
       }}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :invalid_id}
    end
  end

  def resolve_subject("vendor_review_of", id) do
    with {:ok, id} <- parse_id(id),
         %VendorReview{} = review <- Repo.get(VendorReview, id) |> Repo.preload(:artist) do
      {:ok,
       %{
         type: "vendor_review_of",
         record: review,
         display_name: "Review of #{review.artist.nickname}",
         owner_user_id: review.reviewer_id
       }}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :invalid_id}
    end
  end

  def resolve_subject("buyer_review_of", id) do
    with {:ok, id} <- parse_id(id),
         %BuyerReview{} = review <- Repo.get(BuyerReview, id) |> Repo.preload(:buyer) do
      {:ok,
       %{
         type: "buyer_review_of",
         record: review,
         display_name: "Review of #{review.buyer.email}",
         owner_user_id: review.reviewer_id
       }}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :invalid_id}
    end
  end

  def resolve_subject("product_review_of", id) do
    with {:ok, id} <- parse_id(id),
         %ProductReview{} = review <- Repo.get(ProductReview, id) |> Repo.preload(:product) do
      {:ok,
       %{
         type: "product_review_of",
         record: review,
         display_name: "Review of #{review.product.title}",
         owner_user_id: review.reviewer_id
       }}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :invalid_id}
    end
  end

  def resolve_subject(_unsupported_type, _id), do: {:error, :unsupported_subject_type}

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_id(_), do: :error

  @doc """
  Returns the reporter's existing :pending flag on this exact subject, or
  nil. Used by FlagLive.New at mount time to short-circuit the form with a
  "you already reported this" message rather than letting the reporter
  fill it out and hit the partial-unique-index violation on submit.
  """
  def pending_flag_from(reporter_id, subject_type, subject_id) do
    Flag
    |> where(
      reporter_id: ^reporter_id,
      subject_type: ^subject_type,
      subject_id: ^subject_id,
      status: :pending
    )
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Nav badge — pending review counts
  # ---------------------------------------------------------------------------

  def pending_reviews_of_vendor_count(user_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@review_window_days, :day)

    from(o in ArtsyNeighbor.Orders.Order,
      left_join: vr in VendorReview,
      on: vr.order_id == o.id and vr.status == :active,
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
      join: a in ArtsyNeighbor.Artists.Artist,
      on: a.id == o.artist_id,
      left_join: br in BuyerReview,
      on: br.order_id == o.id and br.status == :active,
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
    from(r in VendorReview,
      where: r.reviewer_id == ^user_id and r.status == :active,
      select: r.order_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  # Returns a MapSet of order IDs where the vendor has already submitted a
  # buyer review — used to drive the "Reviewed / Pending" pill on sales rows.
  def reviewed_order_ids_as_vendor(user_id) do
    from(r in BuyerReview,
      where: r.reviewer_id == ^user_id and r.status == :active,
      select: r.order_id
    )
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
  # Soft delete — the day-to-day path. A status flip, not a real Repo.delete,
  # so an admin can still see removed reviews and create_*_review/1 can
  # revive one if the same reviewer resubmits for the same order.
  # ---------------------------------------------------------------------------

  def soft_delete_vendor_review(%VendorReview{} = review, opts \\ []) do
    if opts[:admin] || within_edit_window?(review) do
      review |> VendorReview.status_changeset(%{status: :removed}) |> Repo.update()
    else
      {:error, :edit_window_expired}
    end
  end

  def soft_delete_buyer_review(%BuyerReview{} = review, opts \\ []) do
    if opts[:admin] || within_edit_window?(review) do
      review |> BuyerReview.status_changeset(%{status: :removed}) |> Repo.update()
    else
      {:error, :edit_window_expired}
    end
  end

  def soft_delete_product_review(%ProductReview{} = review, opts \\ []) do
    if opts[:admin] || within_edit_window?(review) do
      review |> ProductReview.status_changeset(%{status: :removed}) |> Repo.update()
    else
      {:error, :edit_window_expired}
    end
  end

  # ---------------------------------------------------------------------------
  # Hard delete — the narrow, exceptional path (dev/testing, or content an
  # admin wants truly gone rather than just hidden). No edit-window gate:
  # unlike soft delete, this isn't a day-to-day action a reviewer reaches for
  # themselves, so there's nothing to bypass. Matches every other entity's
  # hard_delete_<entity>/1 shape (CLAUDE.md) — arity 1, since the opts-based
  # admin bypass that soft_delete_*_review/2 needs doesn't apply here.
  #
  # Each of these also cleans up any Flag rows reporting the review directly
  # ("vendor_review_of"/"buyer_review_of"/"product_review_of") — same class
  # of cleanup as Products.hard_delete_product/1 and Artists.hard_delete_artist/1:
  # Flag.subject_id is a polymorphic reference with no real DB-level FK, so
  # it can't cascade and has to be done by hand.
  # ---------------------------------------------------------------------------

  def hard_delete_vendor_review(%VendorReview{} = review) do
    delete_reviewed_with_flags(review, "vendor_review_of")
  end

  def hard_delete_buyer_review(%BuyerReview{} = review) do
    delete_reviewed_with_flags(review, "buyer_review_of")
  end

  def hard_delete_product_review(%ProductReview{} = review) do
    delete_reviewed_with_flags(review, "product_review_of")
  end

  defp delete_reviewed_with_flags(review, subject_type) do
    Multi.new()
    |> Multi.run(:deleted_flags, fn repo, _changes ->
      {count, _} =
        repo.delete_all(
          from(f in Flag, where: f.subject_type == ^subject_type and f.subject_id == ^review.id)
        )

      {:ok, count}
    end)
    |> Multi.run(:deleted_review, fn repo, _changes -> repo.delete(review) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{deleted_review: deleted}} -> {:ok, deleted}
      {:error, _failed_step, reason, _changes_so_far} -> {:error, reason}
    end
  rescue
    error in [Ecto.ConstraintError, Postgrex.Error] ->
      # A constraint violation Multi's own {:error, ...} tuple can't catch —
      # fail cleanly instead of letting the exception crash the caller.
      {:error, {:constraint_error, Exception.message(error)}}
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
    both_submitted = review_active?(vendor_review) and review_active?(buyer_review)
    both_submitted or window_expired?(order)
  end

  # A soft-deleted review reads as "not submitted" for visibility purposes —
  # its content is hidden regardless of the other party's review or the
  # window, same as if it had never been written.
  defp review_active?(nil), do: false
  defp review_active?(review), do: review.status == :active

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

    my_review = if role == :buyer, do: vendor_review, else: buyer_review
    other_review = if role == :buyer, do: buyer_review, else: vendor_review

    _ = current_user_id

    cond do
      not is_nil(my_review) and not is_nil(other_review) -> :complete
      not is_nil(my_review) and expired -> :published
      not is_nil(my_review) -> :waiting_other_party
      expired -> :expired
      true -> :pending_yours
    end
  end

  defp window_expired?(order) do
    not is_nil(order.completed_at) and
      DateTime.diff(DateTime.utc_now(), order.completed_at, :day) > @review_window_days
  end
end
