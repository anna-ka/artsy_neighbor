defmodule ArtsyNeighbor.Images do
  @moduledoc """
  The one place uploaded photos go through: checks them, turns them
  upright, removes their metadata (GPS location!), makes the web sizes
  and stores everything via `ArtsyNeighbor.Storage`.

  Each processed upload gets a **key**, e.g.
  `"products/12/0b6c5e1a-…"`, which is a folder holding:

    * `source.webp` — at most 4096px on the long side, quality 95,
                      **private** (for re-making sizes later; never
                      shown);
    * `large.webp`  — at most 2500px on the long side, public;
    * `medium.webp` — at most 1600px, public;
    * `thumb.webp`  — at most 800px, public.

  The `path` column of `product_images` / `artist_images` holds either
  such a key or an old-style web path starting with `/` (seed images,
  older uploads). `url/2` handles both.

  See `docs/plans/2026-10-28-image-storage-and-resizing.md`.
  """

  require Logger

  alias ArtsyNeighbor.Storage
  alias ArtsyNeighbor.Images.Limiter

  # Display sizes: name => longest side in pixels. Order matters only
  # for readability.
  @sizes [large: 2500, medium: 1600, thumb: 800]
  @size_names Keyword.keys(@sizes)

  # Smaller than this on the long side looks poor on the product page.
  @min_long_side 800

  # Refuse photos bigger than 52 megapixels (width × height). Phones
  # save 12–24 MP by default and 48–50 MP in their optional big modes
  # (a Pixel's 50 MP photo is 50.1 MP, hence 52). Bigger files, e.g. a
  # Samsung 200 MP photo or a large scan, need too much memory to
  # process on our server (measured 2026-11-06, see the plan doc).
  @max_pixels 52_000_000

  # The private copy we keep is shrunk to at most this on the long side
  # (about 12 MP). Still well above `large`, the biggest size we show.
  # Encoding a full-resolution WebP was the main memory and time cost.
  @source_max_side 4096

  @source_quality 95
  @display_quality 82

  # The libvips "loaders" we accept, i.e. the file formats. libvips can
  # read more (GIF, SVG, PDF, ...), but those are refused on purpose —
  # see the plan doc. `heifload` covers both HEIC and AVIF.
  @allowed_loaders ~w(jpegload pngload webpload tiffload heifload)

  @msg_not_an_image "We couldn't read this file as a photo. Please upload a " <>
                      "JPEG, PNG, HEIC, WebP, TIFF or AVIF image."
  @msg_too_small "This photo is too small to look good. Please use a larger one."
  @msg_too_large "This photo is too large. Please use a smaller version."
  @msg_heic_unsupported "We can't read this iPhone photo format (HEIC) right now. " <>
                          "Please save it as a JPEG and upload that."
  @msg_save_failed "Something went wrong while saving your photo. Please try again."
  @msg_busy "The site is busy — please try again in a moment."

  # The pictures shown when there is no photo. Site images, kept in
  # git under priv/static/images/site/. See placeholder/1.
  @placeholders %{
    artist: "/images/site/avatar-placeholder.png",
    product: "/images/site/placeholder-product.jpg",
    category: "/images/site/placeholder-category.jpg"
  }

  @doc "The display size names: `[:large, :medium, :thumb]`."
  def sizes, do: @size_names

  @doc """
  Processes one uploaded photo and stores it under a new key inside
  `folder` (e.g. `"products/12"`).

  `tmp_path` is the temporary file Phoenix wrote the upload to; it is
  only read, never copied into storage as-is. `client_name` is the
  file's name on the artist's computer, used only in log messages.

  Returns `{:ok, key}`, or `{:error, message}` where `message` is a
  plain-words sentence to show the artist.

  Only a few photos are processed at the same time (see
  `ArtsyNeighbor.Images.Limiter`); this waits for its turn, and if the
  wait is too long it returns the "site is busy" message without
  processing anything. So it can take a while: don't call it while a
  page waits for an answer (the forms call it in a background task,
  see `ArtsyNeighborWeb.PhotoUploads`).

  `folder` is built by our own code from database ids, never from
  what a user typed, so an invalid folder is a programming bug: it
  raises `ArgumentError` (see `Storage.validate_key!/1`) rather than
  returning an error message.
  """
  def process_upload(tmp_path, client_name, folder) do
    key = folder <> "/" <> Ecto.UUID.generate()
    Storage.validate_key!(key)

    result =
      Limiter.run(fn ->
        process_and_store(tmp_path, client_name, key)
      end)

    case result do
      {:error, :busy} -> {:error, @msg_busy}
      other -> other
    end
  end

  defp process_and_store(tmp_path, client_name, key) do
    work_dir = Path.join(System.tmp_dir!(), "artsy_neighbor_image_" <> Ecto.UUID.generate())

    try do
      with :ok <- make_work_dir(work_dir),
           {:ok, image} <- open_image(tmp_path, client_name),
           :ok <- check_format(image, client_name),
           :ok <- check_dimensions(image),
           {:ok, files} <- make_webp_files(tmp_path, work_dir, client_name),
           :ok <- store_files(files, key) do
        {:ok, key}
      end
    after
      File.rm_rf(work_dir)
    end
  end

  @doc """
  The web address to show an image at, in one of the sizes
  `:large`, `:medium` or `:thumb`.

  An old-style path (starting with `/`) is returned unchanged, whatever
  the size: those images only exist in one size.
  """
  def url(nil, _size), do: nil

  def url("/" <> _rest = old_path, size) when size in @size_names, do: old_path

  def url(key, size) when size in @size_names do
    Storage.url(key <> "/" <> Atom.to_string(size) <> ".webp")
  end

  @doc """
  The web address of the first photo in `images` (the one with the
  lowest `position`, i.e. the cover photo the artist chose) in `size`,
  or `placeholder` when there are no photos.

  `images` is a list of `ProductImage` or `ArtistImage` rows; `nil` is
  accepted too and counts as "no photos" (e.g. an order item whose
  product was deleted). Picking the lowest position here (rather than
  trusting the list's order) means every page shows the same cover
  photo, whatever order the photos were loaded in.

  If the photos weren't loaded from the database at all (a query
  without the preload: a programming slip), this shows the placeholder
  and logs a warning, rather than crashing the page.

  ## Examples

      Images.first_url(product.product_images, :thumb, Images.placeholder(:product))
      Images.first_url(artist.artist_images, :thumb)   # nil when no photo
  """
  def first_url(images, size, placeholder \\ nil)

  def first_url(nil, _size, placeholder), do: placeholder

  def first_url(%Ecto.Association.NotLoaded{} = not_loaded, _size, placeholder) do
    Logger.warning(
      "Images.first_url/3 got photos that weren't loaded " <>
        "(#{inspect(not_loaded.__owner__)}.#{not_loaded.__field__}); " <>
        "showing the placeholder. Add the preload to the query."
    )

    placeholder
  end

  def first_url(images, size, placeholder) when is_list(images) do
    # Enum.min_by goes through the list once, keeping the photo with the
    # lowest position; the last argument is what to return for an empty
    # list.
    cover = Enum.min_by(images, fn image -> image.position end, fn -> nil end)

    case cover do
      nil -> placeholder
      image -> url(image.path, size)
    end
  end

  @doc """
  The web address of the picture to show when there is no photo:

    * `:artist`   — an artist without a profile photo;
    * `:product`  — a product without photos;
    * `:category` — a category without a picture.

  Every page uses this rather than writing the path itself, so a
  placeholder can be changed in one place (`@placeholders` above).
  Any other `kind` raises an error, so a misspelling shows up the first
  time the page is shown (or in a test) instead of as a broken image.

  Placeholders are a display choice, not data: something without a
  picture stores `nil` (or has no image rows), never this path, and
  pages pick the placeholder when they draw it. Otherwise changing a
  placeholder would need a database update.

  ## Examples

      Images.placeholder(:artist)
      #=> "/images/site/avatar-placeholder.png"

      Images.first_url(artist.artist_images, :thumb, Images.placeholder(:artist))
  """
  def placeholder(kind), do: Map.fetch!(@placeholders, kind)

  @doc """
  `path` itself if there is one, otherwise the placeholder for `kind`
  (see `placeholder/1`). For pictures stored as a plain path in a
  column, e.g. a category's `main_img`, which is `nil` (or `""` if an
  admin cleared the field) when there is no picture.

  ## Examples

      Images.or_placeholder("/images/cat-painting.jpg", :category)
      #=> "/images/cat-painting.jpg"

      Images.or_placeholder(nil, :category)
      #=> "/images/site/placeholder-category.jpg"
  """
  def or_placeholder(nil, kind), do: placeholder(kind)
  def or_placeholder("", kind), do: placeholder(kind)
  def or_placeholder(path, _kind) when is_binary(path), do: path

  # --- Steps of process_upload ---------------------------------------

  # A private temporary folder for the files we make, removed at the end.
  defp make_work_dir(work_dir) do
    case File.mkdir_p(work_dir) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Couldn't create image work folder #{work_dir}: #{inspect(reason)}")
        {:error, @msg_save_failed}
    end
  end

  # Opening only reads the file's header (libvips is lazy), so this is
  # cheap even for a big photo; the pixels are decoded later, when the
  # first file is written.
  defp open_image(tmp_path, client_name) do
    case Image.open(tmp_path) do
      {:ok, image} ->
        {:ok, image}

      {:error, reason} ->
        Logger.info(
          "Image upload #{inspect(client_name)} refused, can't open: #{inspect(reason)}"
        )

        {:error, @msg_not_an_image}
    end
  end

  defp check_format(image, client_name) do
    loader =
      case Vix.Vips.Image.header_value(image, "vips-loader") do
        {:ok, name} -> name
        _ -> nil
      end

    if loader in @allowed_loaders do
      :ok
    else
      Logger.info("Image upload #{inspect(client_name)} refused, format #{inspect(loader)}")
      {:error, @msg_not_an_image}
    end
  end

  defp check_dimensions(image) do
    width = Image.width(image)
    height = Image.height(image)

    cond do
      width * height > @max_pixels -> {:error, @msg_too_large}
      max(width, height) < @min_long_side -> {:error, @msg_too_small}
      true -> :ok
    end
  end

  # Writes source.webp and the display sizes into `work_dir`.
  # Returns {:ok, [{local_path, file_name, visibility}, ...]}.
  #
  # Reads the upload again from its path rather than reusing the image
  # opened for the checks: from a path, libvips can shrink while
  # reading (e.g. decode a big JPEG at half size straight away), which
  # needs much less memory.
  defp make_webp_files(tmp_path, work_dir, client_name) do
    source_path = Path.join(work_dir, "source.webp")

    # `thumbnail` with `resize: :down` only ever shrinks. It also:
    #   * turns the photo upright using its orientation note (EXIF),
    #   * converts colours to sRGB, the colour space browsers assume
    #     (iPhone photos are in the wider "Display P3"), so the colours
    #     still look right once the colour profile is stripped.
    # Writing the file is where libvips actually decodes the pixels,
    # so a HEIC that can't be decoded fails here, not when opened.
    result =
      with {:ok, upright} <-
             Image.thumbnail(tmp_path, @source_max_side,
               resize: :down,
               autorotate: true,
               export_icc_profile: :srgb
             ),
           {:ok, _} <- write_webp(upright, source_path, @source_quality) do
        make_display_sizes(source_path, work_dir)
      end

    case result do
      {:ok, display_files} ->
        {:ok, [{source_path, "source.webp", :private} | display_files]}

      {:error, reason} ->
        log_message = "Image upload #{inspect(client_name)} failed to process: #{inspect(reason)}"

        if heic_not_supported?(reason) do
          Logger.warning(log_message)
          {:error, @msg_heic_unsupported}
        else
          Logger.info(log_message)
          {:error, @msg_not_an_image}
        end
    end
  end

  # The display sizes are made from source.webp, which is already upright,
  # sRGB and metadata-free. Starting from a file path (not an opened
  # image) lets libvips shrink while reading, which is faster and needs
  # less memory.
  defp make_display_sizes(source_path, work_dir) do
    # The files to make: [{long_side, local_path, file_name}, ...]
    planned =
      for {name, long_side} <- @sizes do
        file_name = Atom.to_string(name) <> ".webp"
        {long_side, Path.join(work_dir, file_name), file_name}
      end

    result =
      each_until_error(planned, fn {long_side, out_path, _file_name} ->
        with {:ok, resized} <- Image.thumbnail(source_path, long_side, resize: :down),
             {:ok, _} <- write_webp(resized, out_path, @display_quality) do
          :ok
        end
      end)

    case result do
      :ok ->
        files =
          for {_long_side, out_path, file_name} <- planned do
            {out_path, file_name, :public}
          end

        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Removes every metadata field first (GPS location, camera details,
  # the colour profile, ...), and asks the writer to strip too, so
  # nothing slips through.
  defp write_webp(image, path, quality) do
    with {:ok, clean} <- Image.remove_metadata(image) do
      Image.write(clean, path, quality: quality, strip_metadata: true)
    end
  end

  # The error libvips gives when it was built without the HEVC decoder
  # (e.g. the `image` library's bundled libvips): "Support for this
  # compression format has not been built in: HEVC". iPhone HEIC photos
  # use HEVC; a missing decoder for anything else gets the general
  # message. See `test/artsy_neighbor/image_setup_test.exs`.
  defp heic_not_supported?(reason) do
    String.contains?(inspect(reason), "HEVC")
  end

  defp store_files(files, key) do
    result =
      each_until_error(files, fn {local_path, file_name, visibility} ->
        Storage.put(local_path, key <> "/" <> file_name, visibility)
      end)

    case result do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Storing image #{key} failed: #{inspect(reason)}")
        # Don't leave half of an image behind. If even that fails,
        # it's logged; the artist sees the same message either way.
        case Storage.delete_prefix(key) do
          :ok ->
            :ok

          {:error, cleanup_reason} ->
            Logger.error("Cleaning up #{key} failed: #{inspect(cleanup_reason)}")
        end

        {:error, @msg_save_failed}
    end
  end

  # Calls `fun` on each item in order, stopping at the first one that
  # returns `{:error, reason}`. Returns `:ok` if every call returned
  # `:ok`, otherwise that first `{:error, reason}`.
  #
  # (Enum.each can't stop early, and Enum.reduce_while needs the
  # {:cont, ...} / {:halt, ...} bookkeeping spelled out each time; this
  # keeps that in one place.)
  defp each_until_error(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
