defmodule ArtsyNeighbor.PhotoFileDeletionTest do
  @moduledoc """
  Deleting a photo's database row also deletes its files from storage
  (NOTES #39): one photo at a time, and every photo of a hard-deleted
  product or artist. Soft deletes keep the files, and old-style paths
  (starting with `/`) are never touched.

  Storage here is `Storage.Local` in a temporary folder (see
  `config/test.exs`).
  """
  use ArtsyNeighbor.DataCase, async: true

  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.ProductsFixtures

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Images
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Storage
  alias ArtsyNeighbor.Storage.Local

  @site_image "priv/static/images/cat-sculpture.jpg"

  # Stores a real processed photo in `folder` (e.g. "products/12") and
  # returns its key. Removed at the end of the test if still there.
  defp store_photo(folder) do
    {:ok, key} = Images.process_upload(@site_image, "cat-sculpture.jpg", folder)

    on_exit(fn -> Storage.delete_prefix(key) end)

    key
  end

  defp files_exist?(key) do
    File.exists?(Local.path_for(key <> "/thumb.webp", :public)) and
      File.exists?(Local.path_for(key <> "/source.webp", :private))
  end

  # The files are deleted in a background task, so this checks a few
  # times (for up to 2 seconds) before giving up.
  defp files_gone?(key, tries_left \\ 40) do
    gone? =
      not File.exists?(Local.path_for(key, :public)) and
        not File.exists?(Local.path_for(key, :private))

    cond do
      gone? ->
        true

      tries_left == 0 ->
        false

      true ->
        Process.sleep(50)
        files_gone?(key, tries_left - 1)
    end
  end

  defp add_product_photo(product, position \\ 1) do
    key = store_photo("products/#{product.id}")

    {:ok, image} =
      Products.create_product_image(%{product_id: product.id, path: key, position: position})

    image
  end

  describe "deleting one photo" do
    test "a product photo's files are deleted with its row" do
      product = product_fixture()
      image = add_product_photo(product)
      assert files_exist?(image.path)

      assert {:ok, _} = Products.delete_product_image(image)
      assert files_gone?(image.path)
    end

    test "an artist photo's files are deleted with its row" do
      artist = artist_fixture()
      # Two photos: the last photo of an :active profile can't be removed.
      artist_image_fixture(artist, %{position: 1})
      key = store_photo("artists/#{artist.id}")
      image = artist_image_fixture(artist, %{path: key, position: 2})

      assert {:ok, _} = Artists.delete_artist_image(image)
      assert files_gone?(key)
    end

    test "a refused delete keeps the files" do
      artist = artist_fixture()
      key = store_photo("artists/#{artist.id}")
      image = artist_image_fixture(artist, %{path: key, position: 1})

      assert {:error, :last_photo_of_active_profile} = Artists.delete_artist_image(image)
      assert files_exist?(key)
    end
  end

  describe "hard deletes" do
    test "hard-deleting a product deletes all its photos' files" do
      product = product_fixture()
      first = add_product_photo(product, 1)
      second = add_product_photo(product, 2)

      assert {:ok, _} = Products.hard_delete_product(product)
      assert files_gone?(first.path)
      assert files_gone?(second.path)
    end

    test "hard-deleting an artist deletes their profile and product photos' files" do
      artist = artist_fixture()
      profile_key = store_photo("artists/#{artist.id}")
      artist_image_fixture(artist, %{path: profile_key, position: 1})

      product = product_fixture(%{artist_id: artist.id})
      product_photo = add_product_photo(product)

      assert {:ok, _} = Artists.hard_delete_artist(artist)
      assert files_gone?(profile_key)
      assert files_gone?(product_photo.path)
    end
  end

  test "soft-deleting a product keeps its photos' files (it can be restored)" do
    product = product_fixture()
    image = add_product_photo(product)

    assert {:ok, _} = Products.soft_delete_product(product)
    assert files_exist?(image.path)
  end

  describe "Images.delete_files/1" do
    test "deletes several photos' files at once" do
      product = product_fixture()
      keys = for _ <- 1..6, do: store_photo("products/#{product.id}")

      assert Images.delete_files(keys) == :ok

      for key <- keys do
        assert files_gone?(key)
      end
    end

    test "leaves old-style paths (starting with /) alone" do
      assert Images.delete_files("/images/cat-sculpture.jpg") == :ok
      assert File.exists?(@site_image)
    end

    test "logs a warning for an unexpected value instead of raising" do
      for unexpected <- [nil, "", "products/12", "../config", "some path"] do
        log =
          ExUnit.CaptureLog.capture_log(fn ->
            assert Images.delete_files(unexpected) == :ok
          end)

        assert log =~ "Not deleting photo files"
      end
    end
  end
end

defmodule ArtsyNeighbor.PhotoFileDeletionCrashTest do
  @moduledoc """
  A storage backend that crashes while deleting must not stop the other
  photos' files from being deleted, and must only end up in the log.

  This swaps the storage backend for the whole app for a moment, so
  it's in its own module with `async: false`: no other test runs at the
  same time.
  """
  use ExUnit.Case, async: false

  alias ArtsyNeighbor.Images

  # Stands in for Storage.Local / Storage.S3: tells the test which
  # folder it was asked to delete, then crashes.
  defmodule CrashingStorage do
    def delete_prefix(prefix) do
      send(Application.fetch_env!(:artsy_neighbor, :crash_test_pid), {:asked_to_delete, prefix})
      raise "storage exploded"
    end
  end

  setup do
    previous = Application.fetch_env!(:artsy_neighbor, ArtsyNeighbor.Storage)
    Application.put_env(:artsy_neighbor, ArtsyNeighbor.Storage, backend: CrashingStorage)
    Application.put_env(:artsy_neighbor, :crash_test_pid, self())

    on_exit(fn ->
      Application.put_env(:artsy_neighbor, ArtsyNeighbor.Storage, previous)
      Application.delete_env(:artsy_neighbor, :crash_test_pid)
    end)
  end

  test "a crash is logged, and the other photos are still attempted" do
    first = "products/1/" <> Ecto.UUID.generate()
    second = "products/1/" <> Ecto.UUID.generate()

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert Images.delete_files([first, second]) == :ok

        assert_receive {:asked_to_delete, ^first}, 2_000
        assert_receive {:asked_to_delete, ^second}, 2_000
        # Give the background task a moment to write its log lines.
        Process.sleep(100)
      end)

    assert log =~ "Deleting photo files #{first} crashed"
    assert log =~ "storage exploded"
  end
end
