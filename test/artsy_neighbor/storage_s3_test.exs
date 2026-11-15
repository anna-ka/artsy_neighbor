defmodule ArtsyNeighbor.Storage.S3Test do
  @moduledoc """
  Tests for the Tigris/S3 storage backend, against `ArtsyNeighbor.FakeS3`
  (an in-memory pretend S3), so they need no account or network.
  What they can't show — that real Tigris accepts our requests and
  serves the public bucket — is checked by hand on the preview (see
  `docs/tigris.md`).

  Not async: the fake S3 has one shared store, and one test switches
  the app's storage backend to S3.
  """
  use ExUnit.Case, async: false

  alias ArtsyNeighbor.{FakeS3, Images, Storage}
  alias ArtsyNeighbor.Storage.S3

  @public_bucket "test-photos"
  @private_bucket "test-originals"
  @site_image "priv/static/images/cat-sculpture.jpg"

  setup do
    start_supervised!(FakeS3)

    previous = Application.get_env(:artsy_neighbor, S3)

    Application.put_env(:artsy_neighbor, S3,
      public_bucket: @public_bucket,
      private_bucket: @private_bucket,
      public_base_url: "https://#{@public_bucket}.example.test",
      ex_aws: [
        http_client: FakeS3,
        access_key_id: "test-key-id",
        secret_access_key: "test-secret",
        scheme: "https://",
        host: "s3.example.test",
        region: "auto",
        virtual_host: true
      ]
    )

    dir = Path.join(System.tmp_dir!(), "storage_s3_test_" <> Ecto.UUID.generate())
    File.mkdir_p!(dir)
    file = Path.join(dir, "photo.webp")
    File.write!(file, "pretend webp bytes")

    on_exit(fn ->
      File.rm_rf!(dir)
      restore_env(S3, previous)
    end)

    %{webp_file: file, dir: dir}
  end

  defp restore_env(name, nil), do: Application.delete_env(:artsy_neighbor, name)
  defp restore_env(name, value), do: Application.put_env(:artsy_neighbor, name, value)

  describe "put/3" do
    test "a public file goes to the public bucket, as WebP, cacheable", %{webp_file: file} do
      assert S3.put(file, "products/1/abc/thumb.webp", :public) == :ok

      stored = FakeS3.get_file(@public_bucket, "products/1/abc/thumb.webp")
      assert stored.body == "pretend webp bytes"
      assert stored.headers["content-type"] == "image/webp"
      assert stored.headers["cache-control"] == "public, max-age=31536000, immutable"

      assert FakeS3.get_file(@private_bucket, "products/1/abc/thumb.webp") == nil
    end

    test "a private file goes to the private bucket only, not cacheable", %{webp_file: file} do
      assert S3.put(file, "products/1/abc/source.webp", :private) == :ok

      stored = FakeS3.get_file(@private_bucket, "products/1/abc/source.webp")
      assert stored.body == "pretend webp bytes"
      refute Map.has_key?(stored.headers, "cache-control")

      assert FakeS3.get_file(@public_bucket, "products/1/abc/source.webp") == nil
    end

    test "a missing local file is an error, nothing is stored", %{dir: dir} do
      missing = Path.join(dir, "not-there.webp")

      assert {:error, :enoent} = S3.put(missing, "products/1/abc/thumb.webp", :public)
      assert FakeS3.stored_keys() == []
    end
  end

  test "url/1 is the public bucket's address plus the key" do
    assert S3.url("products/1/abc/thumb.webp") ==
             "https://test-photos.example.test/products/1/abc/thumb.webp"
  end

  describe "read/2" do
    test "reads from the bucket matching the visibility", %{webp_file: file} do
      :ok = S3.put(file, "artists/2/abc/source.webp", :private)

      assert S3.read("artists/2/abc/source.webp", :private) == {:ok, "pretend webp bytes"}
      assert S3.read("artists/2/abc/source.webp", :public) == {:error, :enoent}
    end
  end

  describe "delete_prefix/1" do
    test "deletes the folder's files in both buckets, and nothing else", %{webp_file: file} do
      :ok = S3.put(file, "products/1/abc/thumb.webp", :public)
      :ok = S3.put(file, "products/1/abc/medium.webp", :public)
      :ok = S3.put(file, "products/1/abc/source.webp", :private)
      # Same start of the name, different folder: must survive.
      :ok = S3.put(file, "products/1/abcd/thumb.webp", :public)
      :ok = S3.put(file, "products/10/abc/thumb.webp", :public)

      assert S3.delete_prefix("products/1/abc") == :ok

      assert FakeS3.stored_keys() == [
               {@public_bucket, "products/1/abcd/thumb.webp"},
               {@public_bucket, "products/10/abc/thumb.webp"}
             ]
    end

    test "deleting a folder that isn't there is fine" do
      assert S3.delete_prefix("products/1/nothing-here") == :ok
    end
  end

  describe "with the app's storage switched to S3" do
    setup do
      previous = Application.get_env(:artsy_neighbor, Storage)
      Application.put_env(:artsy_neighbor, Storage, backend: S3)
      on_exit(fn -> restore_env(Storage, previous) end)
    end

    test "a processed photo lands in the right buckets and can be deleted", %{dir: dir} do
      photo = Path.join(dir, "photo.jpg")
      {:ok, _} = @site_image |> Image.open!() |> Image.write(photo)
      folder = "products/7"

      assert {:ok, key} = Images.process_upload(photo, "photo.jpg", folder)

      assert FakeS3.stored_keys() == [
               {@private_bucket, key <> "/source.webp"},
               {@public_bucket, key <> "/large.webp"},
               {@public_bucket, key <> "/medium.webp"},
               {@public_bucket, key <> "/thumb.webp"}
             ]

      assert Images.url(key, :thumb) == "https://test-photos.example.test/#{key}/thumb.webp"

      assert Storage.delete_prefix(key) == :ok
      assert FakeS3.stored_keys() == []
    end
  end
end
