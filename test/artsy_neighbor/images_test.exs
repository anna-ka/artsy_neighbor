defmodule ArtsyNeighbor.ImagesTest do
  @moduledoc """
  Tests for `ArtsyNeighbor.Images` (and, through it, `Storage.Local`).

  The test photos are made here, from a site image, rather than kept
  as files in the repo: it's then clear how each one was made. The
  only exception is the HEIC photo, which libvips can't reliably
  write on the Mac. Test photos are never made from real phone photos
  (they carry the GPS location of where they were taken).

  Tests tagged `:heic` need a libvips that can decode HEIC; tests
  tagged `:no_heic` need one that can't. `test_helper.exs` checks which
  is the case and skips the other kind.
  """
  use ExUnit.Case, async: true

  alias ArtsyNeighbor.Images
  alias ArtsyNeighbor.Storage
  alias ArtsyNeighbor.Storage.Local

  # 1487 × 998 pixels, landscape.
  @site_image "priv/static/images/cat-sculpture.jpg"
  # 1000 × 671 pixels, landscape, HEVC-encoded, no GPS.
  @heic_fixture "test/support/images/cat-sculpture.heic"

  setup do
    # A fresh folder per test for the test photos, and a unique storage
    # folder so tests running at the same time don't meet.
    dir = Path.join(System.tmp_dir!(), "images_test_" <> Ecto.UUID.generate())
    File.mkdir_p!(dir)
    folder = "test/" <> Ecto.UUID.generate()

    on_exit(fn ->
      File.rm_rf!(dir)
      Storage.delete_prefix(folder)
    end)

    %{dir: dir, folder: folder}
  end

  # --- Helpers ---------------------------------------------------------

  # Saves a copy of the site image as `file_name` (the extension picks
  # the format). `change` can alter the image first, e.g. add metadata.
  defp make_test_photo(dir, file_name, change \\ fn image -> image end) do
    path = Path.join(dir, file_name)
    image = @site_image |> Image.open!() |> change.()
    {:ok, _} = Image.write(image, path)
    path
  end

  # Sets metadata fields on an image. `fields` is a list of
  # {name, type, value}, as libvips names them.
  defp set_metadata(image, fields) do
    {:ok, changed} =
      Vix.Vips.Image.mutate(image, fn mutable ->
        Enum.each(fields, fn {name, type, value} ->
          :ok = Vix.Vips.MutableImage.set(mutable, name, type, value)
        end)
      end)

    changed
  end

  defp stored_path(key, file_name, visibility) do
    Local.path_for(key <> "/" <> file_name, visibility)
  end

  defp metadata_field_names(path) do
    {:ok, names} = path |> Image.open!() |> Vix.Vips.Image.header_field_names()
    names
  end

  # Processes the photo and checks that all four files were stored in
  # the right place, as WebP. Returns the key.
  defp process_and_check(path, folder) do
    assert {:ok, key} = Images.process_upload(path, Path.basename(path), folder)
    assert String.starts_with?(key, folder <> "/")

    assert File.exists?(stored_path(key, "source.webp", :private))
    refute File.exists?(stored_path(key, "source.webp", :public))

    for size <- ["large", "medium", "thumb"] do
      file = stored_path(key, size <> ".webp", :public)
      assert File.exists?(file), "#{size}.webp is missing"
      assert {:ok, "webpload"} = Vix.Vips.Image.header_value(Image.open!(file), "vips-loader")
    end

    key
  end

  # --- Formats -----------------------------------------------------------

  describe "process_upload/3 accepts" do
    for file_name <- ["photo.jpg", "photo.png", "photo.webp", "photo.tif"] do
      test file_name, %{dir: dir, folder: folder} do
        path = make_test_photo(dir, unquote(file_name))
        process_and_check(path, folder)
      end
    end

    @tag :heic
    test "photo.avif", %{dir: dir, folder: folder} do
      path = make_test_photo(dir, "photo.avif")
      process_and_check(path, folder)
    end

    @tag :heic
    test "an iPhone HEIC photo", %{folder: folder} do
      process_and_check(@heic_fixture, folder)
    end
  end

  describe "process_upload/3 sizes" do
    test "never enlarges: a 1487px photo keeps 1487px for source and large",
         %{dir: dir, folder: folder} do
      key = process_and_check(make_test_photo(dir, "photo.jpg"), folder)

      long_side = fn file_name, visibility ->
        image = Image.open!(stored_path(key, file_name, visibility))
        max(Image.width(image), Image.height(image))
      end

      assert long_side.("source.webp", :private) == 1487
      assert long_side.("large.webp", :public) == 1487
      assert long_side.("medium.webp", :public) == 1487
      assert long_side.("thumb.webp", :public) == 800
    end

    test "shrinks a big photo to 4096 (kept copy) and 2500 / 1600 / 800 (shown)",
         %{dir: dir, folder: folder} do
      # 1487 × 3 = 4461px wide.
      path =
        make_test_photo(dir, "big.jpg", fn image ->
          Image.resize!(image, 3.0)
        end)

      key = process_and_check(path, folder)

      assert Image.width(Image.open!(stored_path(key, "source.webp", :private))) == 4096

      sizes =
        for file_name <- ["large.webp", "medium.webp", "thumb.webp"] do
          Image.width(Image.open!(stored_path(key, file_name, :public)))
        end

      assert sizes == [2500, 1600, 800]
    end
  end

  # --- Rotation and metadata -------------------------------------------------

  test "a photo with a 'rotate 90°' orientation note comes out upright",
       %{dir: dir, folder: folder} do
    # Orientation 6 = "rotate 90° clockwise to display", which is what
    # a phone writes for a portrait photo. The pixels stay landscape.
    path =
      make_test_photo(dir, "sideways.jpg", fn image ->
        set_metadata(image, [{"orientation", :gint, 6}])
      end)

    key = process_and_check(path, folder)

    # The pixels themselves are now portrait...
    thumb = Image.open!(stored_path(key, "thumb.webp", :public))
    assert Image.height(thumb) > Image.width(thumb)

    # ...and no orientation note is left that could turn it again.
    refute "orientation" in metadata_field_names(stored_path(key, "thumb.webp", :public))
  end

  test "GPS location and other metadata are removed from every stored file",
       %{dir: dir, folder: folder} do
    # A fake location (1°N, 1°E, in the ocean) — never a real one.
    path =
      make_test_photo(dir, "gps.jpg", fn image ->
        set_metadata(image, [
          {"exif-ifd3-GPSLatitudeRef", :gchararray, "N"},
          {"exif-ifd3-GPSLatitude", :gchararray, "1/1 0/1 0/1"},
          {"exif-ifd3-GPSLongitudeRef", :gchararray, "E"},
          {"exif-ifd3-GPSLongitude", :gchararray, "1/1 0/1 0/1"}
        ])
      end)

    # Check the test photo really carries the location to begin with.
    assert {:ok, %{gps: %{gps_latitude: [1, 0, 0]}}} = Image.exif(Image.open!(path))

    key = process_and_check(path, folder)

    stored_files = [
      stored_path(key, "source.webp", :private),
      stored_path(key, "large.webp", :public),
      stored_path(key, "medium.webp", :public),
      stored_path(key, "thumb.webp", :public)
    ]

    for file <- stored_files do
      names = metadata_field_names(file)

      leftover =
        Enum.filter(names, fn name ->
          String.contains?(name, "GPS") or
            String.starts_with?(name, "exif") or
            String.starts_with?(name, "xmp") or
            String.starts_with?(name, "iptc")
        end)

      assert leftover == [], "#{Path.basename(file)} still has #{inspect(leftover)}"
      assert {:error, _} = Image.exif(Image.open!(file))
    end
  end

  # --- Refusals --------------------------------------------------------------

  describe "process_upload/3 refuses" do
    test "a photo under 800px on the long side", %{dir: dir, folder: folder} do
      path = make_test_photo(dir, "small.jpg", fn image -> Image.thumbnail!(image, 700) end)

      assert {:error, "This photo is too small to look good. Please use a larger one."} =
               Images.process_upload(path, "small.jpg", folder)
    end

    test "a photo over 52 megapixels", %{dir: dir, folder: folder} do
      # 7300 × 7200 = 52.56 million pixels.
      path = Path.join(dir, "huge.png")
      {:ok, _} = 7300 |> Image.new!(7200, color: :white) |> Image.write(path)

      assert {:error, "This photo is too large. Please use a smaller version."} =
               Images.process_upload(path, "huge.png", folder)
    end

    test "a text file renamed to .jpg", %{dir: dir, folder: folder} do
      path = Path.join(dir, "not-a-photo.jpg")
      File.write!(path, "Just some text, not a photo.")

      assert {:error, "We couldn't read this file as a photo." <> _} =
               Images.process_upload(path, "not-a-photo.jpg", folder)
    end

    test "a format we don't accept (GIF), even though libvips can read it",
         %{dir: dir, folder: folder} do
      path = make_test_photo(dir, "photo.gif")

      assert {:error, "We couldn't read this file as a photo." <> _} =
               Images.process_upload(path, "photo.gif", folder)
    end

    test "nothing is stored for a refused photo", %{dir: dir, folder: folder} do
      path = make_test_photo(dir, "small.jpg", fn image -> Image.thumbnail!(image, 700) end)
      {:error, _} = Images.process_upload(path, "small.jpg", folder)

      refute File.exists?(Local.path_for(folder, :public))
      refute File.exists?(Local.path_for(folder, :private))
    end
  end

  # The two halves of process_upload/3, used by the photo forms to check
  # a photo as soon as it's picked and store it at Save.
  describe "prepare_upload/4 and store_prepared/2" do
    test "prepare makes the four files in the work folder without storing anything; store stores them",
         %{dir: dir, folder: folder} do
      work_dir = Path.join(dir, "work")

      assert {:ok, prepared} = Images.prepare_upload(@site_image, "cat.jpg", work_dir)
      assert prepared.dir == work_dir

      for file_name <- ["source.webp", "large.webp", "medium.webp", "thumb.webp"] do
        assert File.exists?(Path.join(work_dir, file_name))
      end

      refute File.exists?(Local.path_for(folder, :public))

      assert {:ok, key} = Images.store_prepared(prepared, folder)
      assert String.starts_with?(key, folder <> "/")
      assert File.exists?(stored_path(key, "source.webp", :private))
      assert File.exists?(stored_path(key, "thumb.webp", :public))

      # Storing leaves the prepared files; discarding removes them.
      assert File.dir?(work_dir)
      Images.discard_prepared(prepared)
      refute File.exists?(work_dir)
    end

    # E.g. a full disk: a problem on our side, so the artist gets "Try
    # again" rather than "remove it". (A folder we can't write to stands
    # in for the full disk.)
    @tag capture_log: true
    test "a good photo whose files can't be written is :failed, not :refused", %{dir: dir} do
      work_dir = Path.join(dir, "read-only")
      File.mkdir_p!(work_dir)
      File.chmod!(work_dir, 0o500)
      on_exit(fn -> File.chmod(work_dir, 0o700) end)

      assert {:error, {:failed, "Something went wrong while saving your photo." <> _}} =
               Images.prepare_upload(@site_image, "cat.jpg", work_dir)
    end

    @tag capture_log: true
    test "a work folder that can't be made is :failed", %{dir: dir} do
      # A file where the folder's parent should be.
      not_a_folder = Path.join(dir, "file")
      File.write!(not_a_folder, "")

      assert {:error, {:failed, _message}} =
               Images.prepare_upload(@site_image, "cat.jpg", Path.join(not_a_folder, "work"))
    end

    test "a photo that can't be used is :refused, and its work folder is removed", %{dir: dir} do
      path = make_test_photo(dir, "small.jpg", fn image -> Image.thumbnail!(image, 400) end)
      work_dir = Path.join(dir, "work")

      assert {:error, {:refused, "This photo is too small to look good." <> _}} =
               Images.prepare_upload(path, "small.jpg", work_dir)

      refute File.exists?(work_dir)
    end

    test ":on_header is told whether the photo is big and how many pictures it holds",
         %{dir: dir} do
      test_pid = self()
      on_header = fn header_info -> send(test_pid, {:header, header_info}) end

      assert {:ok, _prepared} =
               Images.prepare_upload(@site_image, "cat.jpg", Path.join(dir, "work"),
                 on_header: on_header
               )

      assert_received {:header, %{big: false, pictures: :one}}
    end

    test ":on_header isn't called for a photo refused by its header", %{dir: dir} do
      path = make_test_photo(dir, "small.jpg", fn image -> Image.thumbnail!(image, 400) end)
      test_pid = self()
      on_header = fn header_info -> send(test_pid, {:header, header_info}) end

      assert {:error, {:refused, _message}} =
               Images.prepare_upload(path, "small.jpg", Path.join(dir, "work"),
                 on_header: on_header
               )

      refute_received {:header, _header_info}
    end

    # NOTES #44: the artist is told that a moving image becomes a still one.
    test "a moving image: :on_header says so, and only its first picture is kept",
         %{dir: dir} do
      path = Path.join(dir, "moving.webp")
      File.write!(path, ArtsyNeighborWeb.PhotoUploadHelpers.moving_webp())
      test_pid = self()
      on_header = fn header_info -> send(test_pid, {:header, header_info}) end

      assert {:ok, prepared} =
               Images.prepare_upload(path, "moving.webp", Path.join(dir, "work"),
                 on_header: on_header
               )

      assert_received {:header, %{big: false, pictures: :moving_image}}

      # One picture of 1487 × 998, not the two stacked (998 × 2 high).
      source = Image.open!(Path.join(prepared.dir, "source.webp"))
      assert {Image.width(source), Image.height(source)} == {1487, 998}
      assert Vix.Vips.Image.header_value(source, "n-pages") != {:ok, 2}
    end

    test "a TIFF with several pages: :on_header says so, and only the first page is kept",
         %{dir: dir} do
      path = Path.join(dir, "pages.tif")
      File.write!(path, two_page_tiff())
      test_pid = self()
      on_header = fn header_info -> send(test_pid, {:header, header_info}) end

      assert {:ok, prepared} =
               Images.prepare_upload(path, "pages.tif", Path.join(dir, "work"),
                 on_header: on_header
               )

      assert_received {:header, %{big: false, pictures: :several_pages}}

      source = Image.open!(Path.join(prepared.dir, "source.webp"))
      assert {Image.width(source), Image.height(source)} == {1487, 998}
    end
  end

  # A TIFF with two pages (the site image, then the same in negative):
  # the two stacked, with "page-height" telling libvips where each ends.
  defp two_page_tiff do
    page = Image.open!(@site_image)
    {:ok, negative} = Vix.Vips.Operation.invert(page)
    {:ok, negative} = Vix.Vips.Operation.cast(negative, :VIPS_FORMAT_UCHAR)
    {:ok, stacked} = Vix.Vips.Operation.arrayjoin([page, negative], across: 1)

    {:ok, pages} =
      Vix.Vips.Image.mutate(stacked, fn mutable ->
        :ok = Vix.Vips.MutableImage.set(mutable, "page-height", :gint, Image.height(page))
      end)

    {:ok, bytes} = Vix.Vips.Image.write_to_buffer(pages, ".tif")
    bytes
  end

  describe "big_photo?/3" do
    test "HEIC or AVIF (heifload) over 20 megapixels is big" do
      assert Images.big_photo?("heifload", 8064, 6048)
      assert Images.big_photo?("heifload", 5712, 4284)
    end

    test "PNG and TIFF over 20 megapixels are big too: also decoded in full" do
      assert Images.big_photo?("pngload", 8064, 6048)
      assert Images.big_photo?("tiffload", 8064, 6048)
    end

    test "20 megapixels or less is not big" do
      refute Images.big_photo?("heifload", 4032, 3024)
      refute Images.big_photo?("heifload", 5000, 4000)
      refute Images.big_photo?("pngload", 5000, 4000)
    end

    test "JPEG and WebP are never big: they're shrunk while they're read" do
      refute Images.big_photo?("jpegload", 8064, 6048)
      refute Images.big_photo?("webpload", 8064, 6048)
    end
  end

  @tag :no_heic
  test "where libvips can't decode HEIC, the artist gets a plain message",
       %{folder: folder} do
    assert {:error, "We can't read this iPhone photo format (HEIC) right now." <> _} =
             Images.process_upload(@heic_fixture, "IMG_0001.HEIC", folder)
  end

  # --- url/2 -----------------------------------------------------------------

  describe "url/2" do
    test "returns an old-style path unchanged, for every size" do
      for size <- Images.sizes() do
        assert Images.url("/images/mug.jpg", size) == "/images/mug.jpg"
      end
    end

    test "turns a key into the address of that size" do
      key = "products/12/0b6c5e1a-6b8e-4c43-9a43-3c1f2b7e8d90"

      assert Images.url(key, :thumb) == "/uploads/#{key}/thumb.webp"
      assert Images.url(key, :medium) == "/uploads/#{key}/medium.webp"
      assert Images.url(key, :large) == "/uploads/#{key}/large.webp"
    end

    test "nil stays nil" do
      assert Images.url(nil, :thumb) == nil
    end
  end

  describe "placeholder/1" do
    test "each placeholder is a file that exists in priv/static" do
      for kind <- [:artist, :product, :category] do
        web_path = Images.placeholder(kind)
        # app_dir finds the app's priv folder wherever the tests run from.
        file = Path.join(Application.app_dir(:artsy_neighbor, "priv/static"), web_path)

        assert File.exists?(file), "placeholder for #{kind} is missing: #{file}"
      end
    end

    test "an unknown kind raises instead of giving a broken image" do
      assert_raise KeyError, fn -> Images.placeholder(:artsit) end
    end
  end

  describe "or_placeholder/2" do
    test "gives the path itself when there is one" do
      assert Images.or_placeholder("/images/cat-painting.jpg", :category) ==
               "/images/cat-painting.jpg"
    end

    test "gives the placeholder for nil or an empty path" do
      assert Images.or_placeholder(nil, :category) == Images.placeholder(:category)
      assert Images.or_placeholder("", :category) == Images.placeholder(:category)
    end
  end

  describe "first_url/3" do
    test "uses the photo with the lowest position, whatever the list order" do
      # Plain maps stand in for ProductImage / ArtistImage rows: only
      # :path and :position are used.
      images = [
        %{path: "/images/second.jpg", position: 2},
        %{path: "/images/cover.jpg", position: 1},
        %{path: "/images/third.jpg", position: 3}
      ]

      assert Images.first_url(images, :thumb) == "/images/cover.jpg"
    end

    test "gives the address of the chosen size for a key" do
      key = "products/12/0b6c5e1a-6b8e-4c43-9a43-3c1f2b7e8d90"

      assert Images.first_url([%{path: key, position: 1}], :medium) ==
               "/uploads/#{key}/medium.webp"
    end

    test "no photos (empty list or nil) gives the placeholder, or nil without one" do
      assert Images.first_url([], :thumb, "/images/site/placeholder.jpg") ==
               "/images/site/placeholder.jpg"

      assert Images.first_url(nil, :thumb, "/images/site/placeholder.jpg") ==
               "/images/site/placeholder.jpg"

      assert Images.first_url([], :thumb) == nil
    end

    test "photos that weren't loaded give the placeholder and a warning, not a crash" do
      # What a product's product_images holds when the query forgot
      # to preload them.
      not_loaded = %Ecto.Association.NotLoaded{
        __field__: :product_images,
        __owner__: ArtsyNeighbor.Products.Product,
        __cardinality__: :many
      }

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Images.first_url(not_loaded, :thumb, "/images/site/placeholder.jpg") ==
                   "/images/site/placeholder.jpg"
        end)

      assert log =~ "weren't loaded"
      assert log =~ "product_images"
    end
  end

  describe "Storage.delete_prefix/1" do
    test "deletes one image's public and private files", %{dir: dir, folder: folder} do
      {:ok, key} = Images.process_upload(make_test_photo(dir, "photo.jpg"), "photo.jpg", folder)

      assert Storage.delete_prefix(key) == :ok
      refute File.exists?(Local.path_for(key, :public))
      refute File.exists?(Local.path_for(key, :private))
    end

    test "deleting something that isn't there is fine" do
      assert Storage.delete_prefix("products/12/" <> Ecto.UUID.generate()) == :ok
    end

    test "refuses anything broader than one image's folder" do
      for too_broad <- ["products", "products/12", "test"] do
        assert_raise ArgumentError, fn -> Storage.delete_prefix(too_broad) end
      end
    end
  end

  describe "Storage.validate_key!/1" do
    test "accepts our own keys" do
      assert Storage.validate_key!("products/12/0b6c5e1a-6b8e/thumb.webp") == :ok
    end

    test "refuses keys that could point outside the storage folder" do
      for bad <- ["", "/etc/passwd", "../config", "products/../../config", "a//b", "a b", "a/./b"] do
        assert_raise ArgumentError, fn -> Storage.validate_key!(bad) end
      end
    end
  end
end

defmodule ArtsyNeighbor.ImagesInfoLogTest do
  @moduledoc """
  What `Images.process_upload/3` logs at info level: the timing line
  for each stored photo, and why a photo couldn't be decoded.

  The test config only logs warnings, and a single test process can't
  ask for more, so these tests turn on info logging for the whole app
  for a moment. That's why they're in their own module with
  `async: false`: no other test runs at the same time.
  """
  use ExUnit.Case, async: false

  alias ArtsyNeighbor.Images
  alias ArtsyNeighbor.Storage

  # 1487 × 998 pixels, a JPEG.
  @site_image "priv/static/images/cat-sculpture.jpg"
  # 1000 × 671 pixels, HEVC-encoded.
  @heic_fixture "test/support/images/cat-sculpture.heic"

  setup do
    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)

    folder = "test/" <> Ecto.UUID.generate()
    on_exit(fn -> Storage.delete_prefix(folder) end)
    %{folder: folder}
  end

  test "logs one timing line per stored photo", %{folder: folder} do
    log =
      ExUnit.CaptureLog.capture_log([level: :info], fn ->
        {:ok, _key} = Images.process_upload(@site_image, "photo.jpg", folder)
      end)

    assert log =~ ~s(Photo stored #{folder}/)
    assert log =~ ~s("photo.jpg", jpeg 1487×998 \(1.5 MP,)
    assert log =~ ~r/waited \d+ ms, processing \d+ ms, storing \d+ ms; memory/
  end

  # A cut-off HEIC file opens (its header is intact) but fails while
  # decoding, with only libvips' generic "Failed to memory copy image".
  # Where HEIC is supported, that's a broken file, not a missing
  # decoder, so the artist gets the general message.
  @tag :heic
  @tag :tmp_dir
  test "a broken HEIC file, where HEIC is supported, gets the general message",
       %{folder: folder, tmp_dir: tmp_dir} do
    bytes = File.read!(@heic_fixture)
    broken = Path.join(tmp_dir, "broken.heic")
    File.write!(broken, binary_part(bytes, 0, div(byte_size(bytes), 2)))

    log =
      ExUnit.CaptureLog.capture_log([level: :info], fn ->
        assert {:error, "We couldn't read this file as a photo." <> _} =
                 Images.process_upload(broken, "IMG_0002.HEIC", folder)
      end)

    assert log =~ ~s(Image upload "IMG_0002.HEIC" (heifload\) couldn't be decoded)
    refute log =~ "can't decode HEIC"
  end
end

defmodule ArtsyNeighbor.ImagesBigPhotoTest do
  @moduledoc """
  A big photo (NOTES #43) through `ArtsyNeighbor.Images.prepare_upload/4`.

  A real big photo (a 48 MP HEIC is 15 MB) would make the tests slow
  and the repo heavy, so these tests lower the `big_photo_pixels`
  setting instead, and use a small AVIF (read by the same libvips
  loader as HEIC). Changing a setting affects the whole app, hence
  `async: false`: no other test runs meanwhile.

  Tagged `:heic` like the other AVIF test: writing and reading AVIF
  needs the same libheif as HEIC, which the `image` library's bundled
  libvips doesn't have (`test_helper.exs` skips these tests there).
  """
  use ExUnit.Case, async: false

  @moduletag :heic

  alias ArtsyNeighbor.Images
  alias ArtsyNeighbor.Images.Limiter

  setup do
    # 1487 × 998 = 1.48 MP counts as big below 1 MP.
    Application.put_env(:artsy_neighbor, Images, big_photo_pixels: 1_000_000)
    on_exit(fn -> Application.delete_env(:artsy_neighbor, Images) end)

    dir = Path.join(System.tmp_dir!(), "images_big_test_" <> Ecto.UUID.generate())
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    avif = Path.join(dir, "photo.avif")
    File.write!(avif, ArtsyNeighborWeb.PhotoUploadHelpers.avif_photo().content)
    %{dir: dir, avif: avif}
  end

  test "an AVIF over the limit is big; :on_header says so", %{dir: dir, avif: avif} do
    test_pid = self()
    on_header = fn header_info -> send(test_pid, {:header, header_info}) end

    assert {:ok, _prepared} =
             Images.prepare_upload(avif, "photo.avif", Path.join(dir, "work"),
               on_header: on_header
             )

    assert_received {:header, %{big: true, pictures: :one}}
  end

  test "a JPEG of the same size isn't big", %{dir: dir} do
    test_pid = self()
    on_header = fn header_info -> send(test_pid, {:header, header_info}) end

    assert {:ok, _prepared} =
             Images.prepare_upload(
               "priv/static/images/cat-sculpture.jpg",
               "cat.jpg",
               Path.join(dir, "work"),
               on_header: on_header
             )

    assert_received {:header, %{big: false}}
  end

  # The app's own Limiter (max_big 1): while one big photo holds the big
  # photos' slot, a second big photo waits, though a slot is free.
  @tag capture_log: true
  test "a big photo waits while another big photo is being prepared", %{dir: dir, avif: avif} do
    test_pid = self()

    holder =
      spawn(fn ->
        Limiter.run(
          fn ->
            send(test_pid, :holding)

            receive do
              :release -> :ok
            end
          end,
          big: true
        )
      end)

    assert_receive :holding
    on_exit(fn -> send(holder, :release) end)

    # Gives up after 200 ms: it never got a slot.
    assert {:error, {:failed, "The site is busy" <> _}} =
             Images.prepare_upload(avif, "photo.avif", Path.join(dir, "work"), wait_ms: 200)

    # Once the first big photo is done, it goes through.
    send(holder, :release)

    assert {:ok, _prepared} =
             Images.prepare_upload(avif, "photo.avif", Path.join(dir, "work2"), wait_ms: 5_000)
  end
end
