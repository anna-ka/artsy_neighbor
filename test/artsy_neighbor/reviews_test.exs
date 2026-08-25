defmodule ArtsyNeighbor.ReviewsTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Reviews
  alias ArtsyNeighbor.Conversations

  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.ProductsFixtures
  import ArtsyNeighbor.OrdersFixtures
  import ArtsyNeighbor.ReviewsFixtures

  # ---------------------------------------------------------------------------
  # pending_reviews_of_vendor_count/1
  # ---------------------------------------------------------------------------
  describe "pending_reviews_of_vendor_count/1" do
    test "completed order in window, no review, returns 1" do
      buyer = user_fixture()
      artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(3)

      assert Reviews.pending_reviews_of_vendor_count(buyer.id) == 1
      assert order.id
    end

    test "completed order in window, review already submitted, returns 0" do
      buyer = user_fixture()
      artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(3)

      vendor_review_fixture(%{
        order_id: order.id,
        reviewer_id: buyer.id,
        artist_id: artist.id
      })

      assert Reviews.pending_reviews_of_vendor_count(buyer.id) == 0
    end

    test "completed order older than 14 days, returns 0" do
      buyer = user_fixture()
      artist = artist_fixture()
      order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(20)

      assert Reviews.pending_reviews_of_vendor_count(buyer.id) == 0
    end

    test "order is confirmed (not completed), returns 0" do
      buyer = user_fixture()
      artist = artist_fixture()
      order_fixture(buyer_id: buyer.id, artist_id: artist.id, status: :confirmed)

      assert Reviews.pending_reviews_of_vendor_count(buyer.id) == 0
    end

    test "two completed orders, one reviewed, returns 1" do
      buyer = user_fixture()
      artist = artist_fixture()
      reviewed_order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(2)
      order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(4)

      vendor_review_fixture(%{
        order_id: reviewed_order.id,
        reviewer_id: buyer.id,
        artist_id: artist.id
      })

      assert Reviews.pending_reviews_of_vendor_count(buyer.id) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # pending_reviews_of_buyer_count/1
  # ---------------------------------------------------------------------------
  describe "pending_reviews_of_buyer_count/1" do
    test "vendor's completed sale in window, no BuyerReview, returns 1" do
      buyer = user_fixture()
      artist = artist_fixture()
      order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(3)

      assert Reviews.pending_reviews_of_buyer_count(artist.user_id) == 1
    end

    test "vendor already submitted BuyerReview, returns 0" do
      buyer = user_fixture()
      artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(3)

      buyer_review_fixture(%{
        order_id: order.id,
        reviewer_id: artist.user_id,
        buyer_id: buyer.id
      })

      assert Reviews.pending_reviews_of_buyer_count(artist.user_id) == 0
    end

    test "sale outside 14-day window, returns 0" do
      buyer = user_fixture()
      artist = artist_fixture()
      order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(20)

      assert Reviews.pending_reviews_of_buyer_count(artist.user_id) == 0
    end

    test "order belongs to a different vendor, returns 0" do
      buyer = user_fixture()
      artist = artist_fixture()
      other_artist = artist_fixture()
      order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(3)

      assert Reviews.pending_reviews_of_buyer_count(other_artist.user_id) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # update_*/2 and delete_*/2 — 30-day edit window
  # ---------------------------------------------------------------------------
  describe "update_vendor_review/2 and delete_vendor_review/2 edit window" do
    setup do
      buyer = user_fixture()
      artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(1)

      review =
        vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

      %{review: review}
    end

    test "update within 30 days succeeds", %{review: review} do
      assert {:ok, updated} = Reviews.update_vendor_review(review, %{stars: 3})
      assert updated.stars == 3
    end

    test "update after 30 days is refused", %{review: review} do
      review = backdate_submission(review, 31)
      assert Reviews.update_vendor_review(review, %{stars: 3}) == {:error, :edit_window_expired}
    end

    test "delete within 30 days succeeds", %{review: review} do
      assert {:ok, _deleted} = Reviews.delete_vendor_review(review)
    end

    test "delete after 30 days is refused", %{review: review} do
      review = backdate_submission(review, 31)
      assert Reviews.delete_vendor_review(review) == {:error, :edit_window_expired}
    end

    test "delete after 30 days with admin: true overrides the window", %{review: review} do
      review = backdate_submission(review, 31)
      assert {:ok, _deleted} = Reviews.delete_vendor_review(review, admin: true)
    end
  end

  describe "update_buyer_review/2 and delete_buyer_review/2 edit window" do
    setup do
      buyer = user_fixture()
      artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(1)

      review =
        buyer_review_fixture(%{order_id: order.id, reviewer_id: artist.user_id, buyer_id: buyer.id})

      %{review: review}
    end

    test "update within 30 days succeeds", %{review: review} do
      assert {:ok, updated} = Reviews.update_buyer_review(review, %{stars: 3})
      assert updated.stars == 3
    end

    test "update after 30 days is refused", %{review: review} do
      review = backdate_submission(review, 31)
      assert Reviews.update_buyer_review(review, %{stars: 3}) == {:error, :edit_window_expired}
    end

    test "delete within 30 days succeeds", %{review: review} do
      assert {:ok, _deleted} = Reviews.delete_buyer_review(review)
    end

    test "delete after 30 days is refused", %{review: review} do
      review = backdate_submission(review, 31)
      assert Reviews.delete_buyer_review(review) == {:error, :edit_window_expired}
    end

    test "delete after 30 days with admin: true overrides the window", %{review: review} do
      review = backdate_submission(review, 31)
      assert {:ok, _deleted} = Reviews.delete_buyer_review(review, admin: true)
    end
  end

  describe "update_product_review/2 and delete_product_review/2 edit window" do
    setup do
      buyer = user_fixture()
      artist = artist_fixture()
      product = product_fixture(artist_id: artist.id)
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(1)

      review =
        product_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, product_id: product.id})

      %{review: review}
    end

    test "update within 30 days succeeds", %{review: review} do
      assert {:ok, updated} = Reviews.update_product_review(review, %{stars: 3})
      assert updated.stars == 3
    end

    test "update after 30 days is refused", %{review: review} do
      review = backdate_submission(review, 31)
      assert Reviews.update_product_review(review, %{stars: 3}) == {:error, :edit_window_expired}
    end

    test "delete within 30 days succeeds", %{review: review} do
      assert {:ok, _deleted} = Reviews.delete_product_review(review)
    end

    test "delete after 30 days is refused", %{review: review} do
      review = backdate_submission(review, 31)
      assert Reviews.delete_product_review(review) == {:error, :edit_window_expired}
    end

    test "delete after 30 days with admin: true overrides the window", %{review: review} do
      review = backdate_submission(review, 31)
      assert {:ok, _deleted} = Reviews.delete_product_review(review, admin: true)
    end
  end

  # ---------------------------------------------------------------------------
  # review_visible?/3
  # ---------------------------------------------------------------------------
  describe "review_visible?/3" do
    setup do
      buyer = user_fixture()
      artist = artist_fixture()
      %{buyer: buyer, artist: artist}
    end

    test "both reviews submitted, window open, returns true", %{buyer: buyer, artist: artist} do
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(2)
      vr = vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})
      br = buyer_review_fixture(%{order_id: order.id, reviewer_id: artist.user_id, buyer_id: buyer.id})

      assert Reviews.review_visible?(vr, br, order) == true
    end

    test "only one review submitted, window open, returns false", %{buyer: buyer, artist: artist} do
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(2)
      vr = vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

      assert Reviews.review_visible?(vr, nil, order) == false
    end

    test "only one review submitted, window expired, returns true", %{buyer: buyer, artist: artist} do
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(20)
      vr = vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

      assert Reviews.review_visible?(vr, nil, order) == true
    end

    test "neither review submitted, window expired, returns true", %{buyer: buyer, artist: artist} do
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(20)

      assert Reviews.review_visible?(nil, nil, order) == true
    end

    test "neither review submitted, window open, returns false", %{buyer: buyer, artist: artist} do
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(2)

      assert Reviews.review_visible?(nil, nil, order) == false
    end
  end

  # ---------------------------------------------------------------------------
  # list_vendor_reviews_for_artist/1
  # ---------------------------------------------------------------------------
  describe "list_vendor_reviews_for_artist/1" do
    test "both parties submitted, review is returned" do
      buyer = user_fixture()
      artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(2)
      vr = vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})
      buyer_review_fixture(%{order_id: order.id, reviewer_id: artist.user_id, buyer_id: buyer.id})

      result = Reviews.list_vendor_reviews_for_artist(artist.id)
      assert Enum.map(result, & &1.id) == [vr.id]
    end

    test "only vendor submitted, window open, not returned" do
      buyer = user_fixture()
      artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(2)
      vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

      assert Reviews.list_vendor_reviews_for_artist(artist.id) == []
    end

    test "only vendor submitted, window expired, is returned" do
      buyer = user_fixture()
      artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(20)
      vr = vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

      result = Reviews.list_vendor_reviews_for_artist(artist.id)
      assert Enum.map(result, & &1.id) == [vr.id]
    end

    test "review for a different artist, not returned" do
      buyer = user_fixture()
      artist = artist_fixture()
      other_artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(2)
      vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})
      buyer_review_fixture(%{order_id: order.id, reviewer_id: artist.user_id, buyer_id: buyer.id})

      assert Reviews.list_vendor_reviews_for_artist(other_artist.id) == []
    end
  end

  # ---------------------------------------------------------------------------
  # order_in_review_window?/1
  # ---------------------------------------------------------------------------
  describe "order_in_review_window?/1" do
    test "completed_at is nil, returns false" do
      refute Reviews.order_in_review_window?(%{completed_at: nil})
    end

    test "completed 1 day ago, returns true" do
      order = order_fixture(buyer_id: user_fixture().id, artist_id: artist_fixture().id) |> complete_order(1)
      assert Reviews.order_in_review_window?(order) == true
    end

    test "completed 13 days ago, returns true" do
      order = order_fixture(buyer_id: user_fixture().id, artist_id: artist_fixture().id) |> complete_order(13)
      assert Reviews.order_in_review_window?(order) == true
    end

    test "completed exactly 14 days ago, returns false (boundary)" do
      order = order_fixture(buyer_id: user_fixture().id, artist_id: artist_fixture().id) |> complete_order(14)
      assert Reviews.order_in_review_window?(order) == false
    end

    test "completed 20 days ago, returns false" do
      order = order_fixture(buyer_id: user_fixture().id, artist_id: artist_fixture().id) |> complete_order(20)
      assert Reviews.order_in_review_window?(order) == false
    end
  end

  # ---------------------------------------------------------------------------
  # reviewed_order_ids_as_buyer/1 and reviewed_order_ids_as_vendor/1
  # ---------------------------------------------------------------------------
  describe "reviewed_order_ids_as_buyer/1" do
    test "returns a MapSet containing orders the user has reviewed" do
      buyer = user_fixture()
      artist = artist_fixture()
      order1 = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(1)
      order2 = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(2)

      vendor_review_fixture(%{order_id: order1.id, reviewer_id: buyer.id, artist_id: artist.id})
      vendor_review_fixture(%{order_id: order2.id, reviewer_id: buyer.id, artist_id: artist.id})

      result = Reviews.reviewed_order_ids_as_buyer(buyer.id)
      assert %MapSet{} = result
      assert MapSet.equal?(result, MapSet.new([order1.id, order2.id]))
    end

    test "user has reviewed nothing, returns empty MapSet" do
      buyer = user_fixture()
      assert Reviews.reviewed_order_ids_as_buyer(buyer.id) == MapSet.new()
    end

    test "another user's reviews are not included" do
      buyer = user_fixture()
      other_buyer = user_fixture()
      artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(1)
      vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

      assert Reviews.reviewed_order_ids_as_buyer(other_buyer.id) == MapSet.new()
    end
  end

  describe "reviewed_order_ids_as_vendor/1" do
    test "returns a MapSet containing orders the vendor has reviewed" do
      buyer = user_fixture()
      artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(1)
      buyer_review_fixture(%{order_id: order.id, reviewer_id: artist.user_id, buyer_id: buyer.id})

      result = Reviews.reviewed_order_ids_as_vendor(artist.user_id)
      assert %MapSet{} = result
      assert MapSet.equal?(result, MapSet.new([order.id]))
    end
  end

  # ---------------------------------------------------------------------------
  # create_vendor_review/1
  # ---------------------------------------------------------------------------
  describe "create_vendor_review/1" do
    setup do
      buyer = user_fixture()
      artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(1)
      %{buyer: buyer, artist: artist, order: order}
    end

    test "valid attrs returns {:ok, review} with submitted_at set", %{buyer: buyer, artist: artist, order: order} do
      assert {:ok, review} =
               Reviews.create_vendor_review(%{
                 stars: 4,
                 body: "Lovely",
                 order_id: order.id,
                 reviewer_id: buyer.id,
                 artist_id: artist.id
               })

      assert review.submitted_at
    end

    test "missing required field returns {:error, changeset}", %{buyer: buyer, artist: artist, order: order} do
      assert {:error, changeset} =
               Reviews.create_vendor_review(%{
                 order_id: order.id,
                 reviewer_id: buyer.id,
                 artist_id: artist.id
               })

      refute changeset.valid?
    end

    test "stars out of range returns validation error", %{buyer: buyer, artist: artist, order: order} do
      assert {:error, changeset} =
               Reviews.create_vendor_review(%{
                 stars: 0,
                 order_id: order.id,
                 reviewer_id: buyer.id,
                 artist_id: artist.id
               })

      refute changeset.valid?

      assert {:error, changeset} =
               Reviews.create_vendor_review(%{
                 stars: 6,
                 order_id: order.id,
                 reviewer_id: buyer.id,
                 artist_id: artist.id
               })

      refute changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # avg_rating_for_artist/1
  # ---------------------------------------------------------------------------
  describe "avg_rating_for_artist/1" do
    test "averages stars across visible reviews only" do
      buyer1 = user_fixture()
      buyer2 = user_fixture()
      artist = artist_fixture()

      order1 = order_fixture(buyer_id: buyer1.id, artist_id: artist.id) |> complete_order(2)
      vendor_review_fixture(%{order_id: order1.id, reviewer_id: buyer1.id, artist_id: artist.id, stars: 4})
      buyer_review_fixture(%{order_id: order1.id, reviewer_id: artist.user_id, buyer_id: buyer1.id})

      order2 = order_fixture(buyer_id: buyer2.id, artist_id: artist.id) |> complete_order(2)
      vendor_review_fixture(%{order_id: order2.id, reviewer_id: buyer2.id, artist_id: artist.id, stars: 2})
      buyer_review_fixture(%{order_id: order2.id, reviewer_id: artist.user_id, buyer_id: buyer2.id})

      assert Reviews.avg_rating_for_artist(artist.id) == 3.0
    end

    test "no visible reviews returns nil" do
      artist = artist_fixture()
      assert Reviews.avg_rating_for_artist(artist.id) == nil
    end

    test "review not yet visible (blind window) is not counted" do
      buyer1 = user_fixture()
      buyer2 = user_fixture()
      artist = artist_fixture()

      order1 = order_fixture(buyer_id: buyer1.id, artist_id: artist.id) |> complete_order(2)
      vendor_review_fixture(%{order_id: order1.id, reviewer_id: buyer1.id, artist_id: artist.id, stars: 4})
      buyer_review_fixture(%{order_id: order1.id, reviewer_id: artist.user_id, buyer_id: buyer1.id})

      # Not yet visible: only the vendor side has submitted, window still open.
      order2 = order_fixture(buyer_id: buyer2.id, artist_id: artist.id) |> complete_order(2)
      vendor_review_fixture(%{order_id: order2.id, reviewer_id: buyer2.id, artist_id: artist.id, stars: 1})

      assert Reviews.avg_rating_for_artist(artist.id) == 4.0
    end
  end

  # ---------------------------------------------------------------------------
  # Conversations.get_or_create_system_conversation/1
  # ---------------------------------------------------------------------------
  describe "Conversations.get_or_create_system_conversation/1" do
    test "first call creates and returns {:ok, conversation}" do
      user = user_fixture()
      assert {:ok, conversation} = Conversations.get_or_create_system_conversation(user.id)
      assert conversation.conversation_type == :system
      assert conversation.user_id == user.id
    end

    test "second call for same user returns the same conversation" do
      user = user_fixture()
      {:ok, first} = Conversations.get_or_create_system_conversation(user.id)
      {:ok, second} = Conversations.get_or_create_system_conversation(user.id)

      assert first.id == second.id
    end

    test "two different users get two different conversations" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conv1} = Conversations.get_or_create_system_conversation(user1.id)
      {:ok, conv2} = Conversations.get_or_create_system_conversation(user2.id)

      assert conv1.id != conv2.id
    end
  end
end
