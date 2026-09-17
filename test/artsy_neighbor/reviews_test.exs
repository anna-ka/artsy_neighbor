defmodule ArtsyNeighbor.ReviewsTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Reviews
  alias ArtsyNeighbor.Reviews.Flag
  alias ArtsyNeighbor.Conversations
  alias ArtsyNeighbor.Repo

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

      reviewed_order =
        order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(2)

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
        buyer_review_fixture(%{
          order_id: order.id,
          reviewer_id: artist.user_id,
          buyer_id: buyer.id
        })

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
        product_review_fixture(%{
          order_id: order.id,
          reviewer_id: buyer.id,
          product_id: product.id
        })

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
  # delete_vendor_review/2, delete_buyer_review/2, delete_product_review/2 —
  # flag cleanup. Flag.subject_id is a polymorphic reference with no real DB
  # FK, so deleting a reviewed review has to clean up matching flags by
  # hand — same class of cleanup as Products.delete_product/1.
  # ---------------------------------------------------------------------------
  describe "review deletion cleans up flags reporting the review" do
    setup do
      buyer = user_fixture()
      reporter = user_fixture()
      artist = artist_fixture()
      product = product_fixture(%{artist_id: artist.id})
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(1)

      %{buyer: buyer, reporter: reporter, artist: artist, product: product, order: order}
    end

    test "delete_vendor_review/2 removes a flag reporting it", %{
      buyer: buyer,
      reporter: reporter,
      artist: artist,
      order: order
    } do
      review =
        vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

      {:ok, flag} =
        Reviews.create_flag(%{
          subject_type: "vendor_review_of",
          subject_id: review.id,
          reason: "This review looks fake and possibly defamatory.",
          reporter_id: reporter.id
        })

      {:ok, _} = Reviews.delete_vendor_review(review)

      assert Repo.get(Flag, flag.id) == nil
    end

    test "delete_buyer_review/2 removes a flag reporting it", %{
      buyer: buyer,
      reporter: reporter,
      artist: artist,
      order: order
    } do
      review =
        buyer_review_fixture(%{
          order_id: order.id,
          reviewer_id: artist.user_id,
          buyer_id: buyer.id
        })

      {:ok, flag} =
        Reviews.create_flag(%{
          subject_type: "buyer_review_of",
          subject_id: review.id,
          reason: "This review looks fake and possibly defamatory.",
          reporter_id: reporter.id
        })

      {:ok, _} = Reviews.delete_buyer_review(review)

      assert Repo.get(Flag, flag.id) == nil
    end

    test "delete_product_review/2 removes a flag reporting it", %{
      buyer: buyer,
      reporter: reporter,
      product: product,
      order: order
    } do
      review =
        product_review_fixture(%{
          order_id: order.id,
          reviewer_id: buyer.id,
          product_id: product.id
        })

      {:ok, flag} =
        Reviews.create_flag(%{
          subject_type: "product_review_of",
          subject_id: review.id,
          reason: "This review looks fake and possibly defamatory.",
          reporter_id: reporter.id
        })

      {:ok, _} = Reviews.delete_product_review(review)

      assert Repo.get(Flag, flag.id) == nil
    end

    test "deleting one review's flag does not affect a flag on an unrelated review", %{
      buyer: buyer,
      reporter: reporter,
      artist: artist,
      order: order
    } do
      review_a =
        vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

      other_buyer = user_fixture()
      other_artist = artist_fixture()

      other_order =
        order_fixture(buyer_id: other_buyer.id, artist_id: other_artist.id) |> complete_order(1)

      review_b =
        vendor_review_fixture(%{
          order_id: other_order.id,
          reviewer_id: other_buyer.id,
          artist_id: other_artist.id
        })

      {:ok, unrelated_flag} =
        Reviews.create_flag(%{
          subject_type: "vendor_review_of",
          subject_id: review_b.id,
          reason: "Unrelated flag on a different vendor review entirely.",
          reporter_id: reporter.id
        })

      {:ok, _} = Reviews.delete_vendor_review(review_a)

      assert Repo.get(Flag, unrelated_flag.id) != nil
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

      vr =
        vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

      br =
        buyer_review_fixture(%{
          order_id: order.id,
          reviewer_id: artist.user_id,
          buyer_id: buyer.id
        })

      assert Reviews.review_visible?(vr, br, order) == true
    end

    test "only one review submitted, window open, returns false", %{buyer: buyer, artist: artist} do
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(2)

      vr =
        vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

      assert Reviews.review_visible?(vr, nil, order) == false
    end

    test "only one review submitted, window expired, returns true", %{
      buyer: buyer,
      artist: artist
    } do
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(20)

      vr =
        vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

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

      vr =
        vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

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

      vr =
        vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

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
      order =
        order_fixture(buyer_id: user_fixture().id, artist_id: artist_fixture().id)
        |> complete_order(1)

      assert Reviews.order_in_review_window?(order) == true
    end

    test "completed 13 days ago, returns true" do
      order =
        order_fixture(buyer_id: user_fixture().id, artist_id: artist_fixture().id)
        |> complete_order(13)

      assert Reviews.order_in_review_window?(order) == true
    end

    test "completed exactly 14 days ago, returns false (boundary)" do
      order =
        order_fixture(buyer_id: user_fixture().id, artist_id: artist_fixture().id)
        |> complete_order(14)

      assert Reviews.order_in_review_window?(order) == false
    end

    test "completed 20 days ago, returns false" do
      order =
        order_fixture(buyer_id: user_fixture().id, artist_id: artist_fixture().id)
        |> complete_order(20)

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

    test "valid attrs returns {:ok, review} with submitted_at set", %{
      buyer: buyer,
      artist: artist,
      order: order
    } do
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

    test "missing required field returns {:error, changeset}", %{
      buyer: buyer,
      artist: artist,
      order: order
    } do
      assert {:error, changeset} =
               Reviews.create_vendor_review(%{
                 order_id: order.id,
                 reviewer_id: buyer.id,
                 artist_id: artist.id
               })

      refute changeset.valid?
    end

    test "stars out of range returns validation error", %{
      buyer: buyer,
      artist: artist,
      order: order
    } do
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

      vendor_review_fixture(%{
        order_id: order1.id,
        reviewer_id: buyer1.id,
        artist_id: artist.id,
        stars: 4
      })

      buyer_review_fixture(%{
        order_id: order1.id,
        reviewer_id: artist.user_id,
        buyer_id: buyer1.id
      })

      order2 = order_fixture(buyer_id: buyer2.id, artist_id: artist.id) |> complete_order(2)

      vendor_review_fixture(%{
        order_id: order2.id,
        reviewer_id: buyer2.id,
        artist_id: artist.id,
        stars: 2
      })

      buyer_review_fixture(%{
        order_id: order2.id,
        reviewer_id: artist.user_id,
        buyer_id: buyer2.id
      })

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

      vendor_review_fixture(%{
        order_id: order1.id,
        reviewer_id: buyer1.id,
        artist_id: artist.id,
        stars: 4
      })

      buyer_review_fixture(%{
        order_id: order1.id,
        reviewer_id: artist.user_id,
        buyer_id: buyer1.id
      })

      # Not yet visible: only the vendor side has submitted, window still open.
      order2 = order_fixture(buyer_id: buyer2.id, artist_id: artist.id) |> complete_order(2)

      vendor_review_fixture(%{
        order_id: order2.id,
        reviewer_id: buyer2.id,
        artist_id: artist.id,
        stars: 1
      })

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

  # ---------------------------------------------------------------------------
  # create_flag/1
  # ---------------------------------------------------------------------------
  describe "create_flag/1" do
    test "a valid vendor flag succeeds" do
      reporter = user_fixture()
      artist = artist_fixture()

      assert {:ok, flag} =
               Reviews.create_flag(%{
                 subject_type: "vendor",
                 subject_id: artist.id,
                 reason: "This vendor never showed up for the scheduled pickup.",
                 reporter_id: reporter.id
               })

      assert flag.status == :pending
    end

    test "a valid buyer flag succeeds" do
      reporter = user_fixture()
      buyer = user_fixture()

      assert {:ok, _flag} =
               Reviews.create_flag(%{
                 subject_type: "buyer",
                 subject_id: buyer.id,
                 reason: "This buyer was abusive in messages during pickup.",
                 reporter_id: reporter.id
               })
    end

    test "a valid product flag succeeds — regression guard for the \"product\" subject type" do
      reporter = user_fixture()
      product = product_fixture()

      assert {:ok, flag} =
               Reviews.create_flag(%{
                 subject_type: "product",
                 subject_id: product.id,
                 reason: "This listing appears to be selling something illegal.",
                 reporter_id: reporter.id
               })

      assert flag.subject_type == "product"
    end

    test "an invalid subject_type is rejected" do
      reporter = user_fixture()

      assert {:error, changeset} =
               Reviews.create_flag(%{
                 subject_type: "not_a_real_type",
                 subject_id: 1,
                 reason: "This should not be accepted by the changeset.",
                 reporter_id: reporter.id
               })

      assert "must be one of: vendor, buyer, product, vendor_review_of, buyer_review_of, product_review_of" in errors_on(
               changeset
             ).subject_type
    end

    test "reason under 20 characters is rejected" do
      reporter = user_fixture()
      artist = artist_fixture()

      assert {:error, changeset} =
               Reviews.create_flag(%{
                 subject_type: "vendor",
                 subject_id: artist.id,
                 reason: String.duplicate("a", 19),
                 reporter_id: reporter.id
               })

      assert "please describe your concern in at least 20 characters" in errors_on(changeset).reason
    end

    test "reason at exactly 20 characters is accepted" do
      reporter = user_fixture()
      artist = artist_fixture()

      assert {:ok, _flag} =
               Reviews.create_flag(%{
                 subject_type: "vendor",
                 subject_id: artist.id,
                 reason: String.duplicate("a", 20),
                 reporter_id: reporter.id
               })
    end

    test "reason over 1000 characters is rejected" do
      reporter = user_fixture()
      artist = artist_fixture()

      assert {:error, changeset} =
               Reviews.create_flag(%{
                 subject_type: "vendor",
                 subject_id: artist.id,
                 reason: String.duplicate("a", 1001),
                 reporter_id: reporter.id
               })

      assert changeset.errors[:reason]
    end

    test "a second pending flag from the same reporter on the same subject is rejected" do
      reporter = user_fixture()
      artist = artist_fixture()

      flag_fixture(%{subject_id: artist.id, reporter_id: reporter.id})

      assert {:error, changeset} =
               Reviews.create_flag(%{
                 subject_type: "vendor",
                 subject_id: artist.id,
                 reason: "Filing a second report on the exact same vendor.",
                 reporter_id: reporter.id
               })

      assert "you have already flagged this" in errors_on(changeset).reporter_id
    end

    test "a different reporter flagging the same subject succeeds" do
      artist = artist_fixture()
      first_reporter = user_fixture()
      second_reporter = user_fixture()

      flag_fixture(%{subject_id: artist.id, reporter_id: first_reporter.id})

      assert {:ok, _flag} =
               Reviews.create_flag(%{
                 subject_type: "vendor",
                 subject_id: artist.id,
                 reason: "A completely different reporter's account of events.",
                 reporter_id: second_reporter.id
               })
    end

    test "once the first flag is resolved, the same reporter can flag the same subject again" do
      reporter = user_fixture()
      admin = user_fixture()
      artist = artist_fixture()

      first_flag = flag_fixture(%{subject_id: artist.id, reporter_id: reporter.id})
      {:ok, _resolved} = Reviews.resolve_flag(first_flag, admin.id)

      assert {:ok, second_flag} =
               Reviews.create_flag(%{
                 subject_type: "vendor",
                 subject_id: artist.id,
                 reason: "Filing again since the first report was already resolved.",
                 reporter_id: reporter.id
               })

      assert second_flag.status == :pending
    end
  end

  # ---------------------------------------------------------------------------
  # pending_flag_from/3
  # ---------------------------------------------------------------------------
  describe "pending_flag_from/3" do
    test "returns the pending flag when one exists" do
      reporter = user_fixture()
      artist = artist_fixture()
      flag = flag_fixture(%{subject_id: artist.id, reporter_id: reporter.id})

      result = Reviews.pending_flag_from(reporter.id, "vendor", artist.id)

      assert result.id == flag.id
    end

    test "returns nil when no flag exists" do
      reporter = user_fixture()
      artist = artist_fixture()

      assert Reviews.pending_flag_from(reporter.id, "vendor", artist.id) == nil
    end

    test "returns nil when the only flag on the subject is already resolved" do
      reporter = user_fixture()
      admin = user_fixture()
      artist = artist_fixture()

      flag = flag_fixture(%{subject_id: artist.id, reporter_id: reporter.id})
      {:ok, _} = Reviews.resolve_flag(flag, admin.id)

      assert Reviews.pending_flag_from(reporter.id, "vendor", artist.id) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_subject/2
  # ---------------------------------------------------------------------------
  describe "resolve_subject/2" do
    test "\"vendor\" resolves to the artist" do
      artist = artist_fixture()

      assert {:ok, resolved} = Reviews.resolve_subject("vendor", artist.id)
      assert resolved.type == "vendor"
      assert resolved.record.id == artist.id
      assert resolved.display_name == artist.nickname
      assert resolved.owner_user_id == artist.user_id
    end

    test "\"buyer\" resolves to the user" do
      buyer = user_fixture()

      assert {:ok, resolved} = Reviews.resolve_subject("buyer", buyer.id)
      assert resolved.type == "buyer"
      assert resolved.record.id == buyer.id
      assert resolved.display_name == buyer.email
      assert resolved.owner_user_id == buyer.id
    end

    test "\"product\" resolves to the product, with the owning artist's user_id" do
      artist = artist_fixture()
      product = product_fixture(%{artist_id: artist.id})

      assert {:ok, resolved} = Reviews.resolve_subject("product", product.id)
      assert resolved.type == "product"
      assert resolved.record.id == product.id
      assert resolved.display_name == product.title
      assert resolved.owner_user_id == artist.user_id
    end

    test "accepts a stringified id, e.g. as it arrives from a URL param" do
      artist = artist_fixture()
      assert {:ok, _resolved} = Reviews.resolve_subject("vendor", to_string(artist.id))
    end

    test "returns {:error, :not_found} for a nonexistent id" do
      assert Reviews.resolve_subject("vendor", 0) == {:error, :not_found}
      assert Reviews.resolve_subject("buyer", 0) == {:error, :not_found}
      assert Reviews.resolve_subject("product", 0) == {:error, :not_found}
    end

    test "returns {:error, :invalid_id} for a non-numeric id" do
      assert Reviews.resolve_subject("vendor", "not-a-number") == {:error, :invalid_id}
    end

    test "returns {:error, :unsupported_subject_type} for a genuinely unsupported subject_type" do
      artist = artist_fixture()
      assert Reviews.resolve_subject("garbage", artist.id) == {:error, :unsupported_subject_type}
      assert Reviews.resolve_subject("buyer", "") == {:error, :invalid_id}
    end

    # The three *_review_of types are handled for consistency, even though
    # no UI links to flagging a review yet (see CLAUDE.md) — reviews aren't
    # shown publicly anywhere, only to the two parties on that order.
    test "\"vendor_review_of\" resolves to the review, owned by its reviewer" do
      buyer = user_fixture()
      artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(1)

      review =
        vendor_review_fixture(%{order_id: order.id, reviewer_id: buyer.id, artist_id: artist.id})

      assert {:ok, resolved} = Reviews.resolve_subject("vendor_review_of", review.id)
      assert resolved.type == "vendor_review_of"
      assert resolved.record.id == review.id
      assert resolved.display_name == "Review of #{artist.nickname}"
      assert resolved.owner_user_id == buyer.id
    end

    test "\"buyer_review_of\" resolves to the review, owned by its reviewer" do
      buyer = user_fixture()
      artist = artist_fixture()
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(1)

      review =
        buyer_review_fixture(%{
          order_id: order.id,
          reviewer_id: artist.user_id,
          buyer_id: buyer.id
        })

      assert {:ok, resolved} = Reviews.resolve_subject("buyer_review_of", review.id)
      assert resolved.type == "buyer_review_of"
      assert resolved.record.id == review.id
      assert resolved.display_name == "Review of #{buyer.email}"
      assert resolved.owner_user_id == artist.user_id
    end

    test "\"product_review_of\" resolves to the review, owned by its reviewer" do
      buyer = user_fixture()
      artist = artist_fixture()
      product = product_fixture(%{artist_id: artist.id})
      order = order_fixture(buyer_id: buyer.id, artist_id: artist.id) |> complete_order(1)

      review =
        product_review_fixture(%{
          order_id: order.id,
          reviewer_id: buyer.id,
          product_id: product.id
        })

      assert {:ok, resolved} = Reviews.resolve_subject("product_review_of", review.id)
      assert resolved.type == "product_review_of"
      assert resolved.record.id == review.id
      assert resolved.display_name == "Review of #{product.title}"
      assert resolved.owner_user_id == buyer.id
    end

    test "returns {:error, :not_found} for a nonexistent review id" do
      assert Reviews.resolve_subject("vendor_review_of", 0) == {:error, :not_found}
      assert Reviews.resolve_subject("buyer_review_of", 0) == {:error, :not_found}
      assert Reviews.resolve_subject("product_review_of", 0) == {:error, :not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # get_flags_for/2
  # ---------------------------------------------------------------------------
  describe "get_flags_for/2" do
    test "returns flags matching subject_type and subject_id" do
      reporter = user_fixture()
      artist = artist_fixture()
      flag = flag_fixture(%{subject_id: artist.id, reporter_id: reporter.id})

      assert [result] = Reviews.get_flags_for("vendor", artist.id)
      assert result.id == flag.id
    end

    test "does not return flags for a different subject" do
      reporter = user_fixture()
      artist_a = artist_fixture()
      artist_b = artist_fixture()
      flag_fixture(%{subject_id: artist_b.id, reporter_id: reporter.id})

      assert Reviews.get_flags_for("vendor", artist_a.id) == []
    end
  end
end
