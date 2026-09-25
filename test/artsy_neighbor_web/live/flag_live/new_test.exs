defmodule ArtsyNeighborWeb.FlagLive.NewTest do
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.ProductsFixtures
  import ArtsyNeighbor.ReviewsFixtures

  alias ArtsyNeighbor.Reviews

  describe "mount / render" do
    test "valid vendor subject shows the confirmation banner", %{conn: conn} do
      reporter = user_fixture()
      artist = artist_fixture()

      {:ok, _live, html} =
        conn
        |> log_in_user(reporter)
        |> live(~p"/flag/vendor/#{artist.id}")

      assert html =~ artist.nickname
    end

    test "valid buyer subject (reported by a vendor) shows the confirmation banner", %{conn: conn} do
      vendor_user = user_fixture()
      artist_fixture(%{user_id: vendor_user.id})
      buyer = user_fixture()

      {:ok, _live, html} =
        conn
        |> log_in_user(vendor_user)
        |> live(~p"/flag/buyer/#{buyer.id}")

      assert html =~ buyer.email
    end

    test "valid product subject shows the confirmation banner", %{conn: conn} do
      reporter = user_fixture()
      product = product_fixture()

      {:ok, _live, html} =
        conn
        |> log_in_user(reporter)
        |> live(~p"/flag/product/#{product.id}")

      assert html =~ product.title
    end

    test "nonexistent subject_id redirects with an error flash", %{conn: conn} do
      reporter = user_fixture()

      assert {:error, {:live_redirect, %{flash: flash}}} =
               conn
               |> log_in_user(reporter)
               |> live(~p"/flag/vendor/999999")

      assert %{"error" => msg} = flash
      assert msg =~ "couldn't find"
    end

    test "unsupported subject_type redirects with an error flash", %{conn: conn} do
      reporter = user_fixture()

      # "vendor_review_of" stays schema-valid on Flag itself, but nothing in
      # the UI links to it yet, so the resolver refuses it too.
      assert {:error, {:live_redirect, %{flash: flash}}} =
               conn
               |> log_in_user(reporter)
               |> live(~p"/flag/vendor_review_of/1")

      assert %{"error" => msg} = flash
      assert msg =~ "couldn't find"
    end

    test "a vendor cannot flag their own artist profile", %{conn: conn} do
      user = user_fixture()
      artist = artist_fixture(%{user_id: user.id})

      assert {:error, {:live_redirect, %{flash: flash}}} =
               conn
               |> log_in_user(user)
               |> live(~p"/flag/vendor/#{artist.id}")

      assert %{"error" => msg} = flash
      assert msg =~ "can't report yourself"
    end

    test "a vendor cannot flag their own product", %{conn: conn} do
      user = user_fixture()
      artist = artist_fixture(%{user_id: user.id})
      product = product_fixture(%{artist_id: artist.id})

      assert {:error, {:live_redirect, %{flash: flash}}} =
               conn
               |> log_in_user(user)
               |> live(~p"/flag/product/#{product.id}")

      assert %{"error" => msg} = flash
      assert msg =~ "can't report yourself"
    end

    test "a plain buyer (no artist profile) cannot flag a buyer", %{conn: conn} do
      reporter = user_fixture()
      buyer = user_fixture()

      assert {:error, {:live_redirect, %{flash: flash}}} =
               conn
               |> log_in_user(reporter)
               |> live(~p"/flag/buyer/#{buyer.id}")

      assert %{"error" => msg} = flash
      assert msg =~ "Only vendors"
    end

    test "an existing pending flag from this reporter skips the form", %{conn: conn} do
      reporter = user_fixture()
      artist = artist_fixture()
      flag_fixture(%{subject_id: artist.id, reporter_id: reporter.id})

      {:ok, _live, html} =
        conn
        |> log_in_user(reporter)
        |> live(~p"/flag/vendor/#{artist.id}")

      assert html =~ "already reported"
      refute html =~ "Submit report"
    end

    test "a resolved prior flag from this reporter does not block a new report", %{conn: conn} do
      reporter = user_fixture()
      admin = user_fixture()
      artist = artist_fixture()
      prior = flag_fixture(%{subject_id: artist.id, reporter_id: reporter.id})
      {:ok, _} = Reviews.resolve_flag(prior, admin.id)

      {:ok, _live, html} =
        conn
        |> log_in_user(reporter)
        |> live(~p"/flag/vendor/#{artist.id}")

      refute html =~ "already reported"
      assert html =~ "Submit report"
    end
  end

  describe "submit" do
    test "under 20 characters shows an inline error and creates nothing", %{conn: conn} do
      reporter = user_fixture()
      artist = artist_fixture()

      {:ok, live, _html} =
        conn
        |> log_in_user(reporter)
        |> live(~p"/flag/vendor/#{artist.id}")

      render_change(live, "form_changed", %{"reason" => "too short"})
      html = render_submit(live, "submit", %{})

      assert html =~ "at least 20 characters"
      assert Reviews.get_flags_for("vendor", artist.id) == []
    end

    test "a valid submission creates a flag, flashes, and navigates to return_to", %{conn: conn} do
      reporter = user_fixture()
      artist = artist_fixture()

      {:ok, live, _html} =
        conn
        |> log_in_user(reporter)
        |> live(
          ~p"/flag/vendor/#{artist.id}?#{[return_to: "/artists/#{artist.id}", return_label: "Artist profile"]}"
        )

      render_change(live, "form_changed", %{
        "reason" => "This vendor never showed up for the scheduled pickup."
      })

      render_submit(live, "submit", %{})

      assert_redirect(live, "/artists/#{artist.id}")

      assert [flag] = Reviews.get_flags_for("vendor", artist.id)
      assert flag.reporter_id == reporter.id
      assert flag.reason == "This vendor never showed up for the scheduled pickup."
    end

    test "a valid submission with no return_to falls back to the homepage", %{conn: conn} do
      reporter = user_fixture()
      artist = artist_fixture()

      {:ok, live, _html} =
        conn
        |> log_in_user(reporter)
        |> live(~p"/flag/vendor/#{artist.id}")

      render_change(live, "form_changed", %{
        "reason" => "This vendor never showed up for the scheduled pickup."
      })

      render_submit(live, "submit", %{})

      assert_redirect(live, "/")
    end

    test "submitting a duplicate pending flag (defensive path) shows an inline message", %{
      conn: conn
    } do
      reporter = user_fixture()
      artist = artist_fixture()

      {:ok, live, _html} =
        conn
        |> log_in_user(reporter)
        |> live(~p"/flag/vendor/#{artist.id}")

      # Simulate a flag going pending in the gap between mount and submit —
      # the mount-time check already passed, so the form is on screen.
      flag_fixture(%{subject_id: artist.id, reporter_id: reporter.id})

      render_change(live, "form_changed", %{
        "reason" => "Filing a second report while the first is still pending."
      })

      html = render_submit(live, "submit", %{})

      assert html =~ "already have a pending report"
    end
  end
end
