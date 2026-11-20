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

  # WebP "effort" (0–6): how hard the encoder works to make the file
  # small. It doesn't change how the photo looks (`quality` does that),
  # only the file size and the time. Measured on the Mac, 2026-11-17,
  # for a 12 MP photo: source.webp at effort 4 (the default) 733 ms,
  # at effort 0 238 ms and even 2% smaller; for a 2500 px display
  # size, effort 2 is twice as fast as 4 for files 0.5% bigger. The
  # source is private, so its size hardly matters; the display sizes
  # are downloaded by visitors, so they get a little more effort.
  @source_effort 0
  @display_effort 2

  # How many of a photo's files are written to storage at the same time
  # (it has four). On Tigris each file is a network request, so most of
  # the time is waiting, not work.
  @store_concurrency 4

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

  # The three below are for the photo pickers, whose browser code
  # (assets/js/photo_shrink.js) shrinks big photos before uploading
  # and must use the same numbers and words as the server.

  @doc "The largest photo we accept, in pixels (width × height)."
  def max_pixels, do: @max_pixels

  @doc "The long side, in pixels, of the private copy we keep (`source.webp`)."
  def source_max_side, do: @source_max_side

  @doc "The message for a photo over `max_pixels/0`."
  def too_large_message, do: @msg_too_large

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
    case process_upload_with_timings(tmp_path, client_name, folder) do
      {:ok, key, _timings} -> {:ok, key}
      {:error, message} -> {:error, message}
    end
  end

  @doc """
  Same as `process_upload/3`, but on success also returns how long the
  steps took: `{:ok, key, %{waited_ms: ..., processing_ms: ...,
  storing_ms: ...}}` (the numbers of the timing log line). Used by
  `ArtsyNeighbor.Images.Timing`.
  """
  def process_upload_with_timings(tmp_path, client_name, folder) do
    key = folder <> "/" <> Ecto.UUID.generate()
    Storage.validate_key!(key)

    asked_at = now_ms()

    result =
      Limiter.run(fn ->
        waited_ms = now_ms() - asked_at
        process_and_store(tmp_path, client_name, key, waited_ms)
      end)

    case result do
      {:error, :busy} -> {:error, @msg_busy}
      other -> other
    end
  end

  @doc """
  Checks, without processing or storing anything, that the photo file
  at `path` would get past `process_upload/3`'s checks: a format we
  take, not too small, not too large. Returns `:ok` or
  `{:error, message}`. Used by the sample data's tests, so a sample
  photo can't fail halfway through filling the preview.
  """
  def check_file(path) do
    name = Path.basename(path)

    with {:ok, image} <- open_image(path, name),
         {:ok, _loader} <- check_format(image, name) do
      check_dimensions(image)
    end
  end

  defp process_and_store(tmp_path, client_name, key, waited_ms) do
    work_dir = Path.join(System.tmp_dir!(), "artsy_neighbor_image_" <> Ecto.UUID.generate())

    try do
      # The two slow steps are wrapped in `timed/1`, which returns
      # {milliseconds, result}; the `else` below unwraps their errors.
      with :ok <- make_work_dir(work_dir),
           {:ok, image} <- open_image(tmp_path, client_name),
           {:ok, loader} <- check_format(image, client_name),
           :ok <- check_dimensions(image),
           {processing_ms, {:ok, files}} <-
             timed(fn -> make_webp_files(tmp_path, work_dir, client_name, loader) end),
           {storing_ms, :ok} <- timed(fn -> store_files(files, key) end) do
        log_timing(%{
          key: key,
          client_name: client_name,
          tmp_path: tmp_path,
          image: image,
          loader: loader,
          waited_ms: waited_ms,
          processing_ms: processing_ms,
          storing_ms: storing_ms
        })

        timings = %{waited_ms: waited_ms, processing_ms: processing_ms, storing_ms: storing_ms}
        {:ok, key, timings}
      else
        {_ms, {:error, message}} -> {:error, message}
        {:error, message} -> {:error, message}
      end
    after
      File.rm_rf(work_dir)
    end
  end

  # How many photos' files are deleted at the same time, e.g. when an
  # artist with many products is hard-deleted.
  @delete_concurrency 4

  @doc """
  Deletes the files of photos whose database rows have been deleted.
  Takes one `path` (a row's `path` value) or a list of them.

    * A key (an image folder such as `"products/12/0b6c5e1a-…"`): its
      folder is deleted, public sizes and private `source.webp` alike.
    * An old-style path starting with `/` (seed images, older uploads
      under `priv/static`): left alone; those files are part of the app
      or the dev data, not ours to delete.
    * Anything else (`nil`, a malformed value): left alone, with a
      warning in the log.

  The deleting happens **in the background** (a task under
  `ArtsyNeighbor.TaskSupervisor`), a few photos at a time: on Tigris each
  photo takes a few requests, and the page that asked shouldn't wait
  for them. This returns `:ok` straight away and never raises.

  If deleting fails (storage can't be reached, or even raises), it is
  logged and the files stay behind: the database delete has already
  happened and the photo is gone from the site, so there is nothing
  useful to tell the artist. A periodic clean-up of folders no row
  points to would catch these (NOTES #42).

  Call it only after the transaction that deleted the rows has
  committed: if the transaction were rolled back, the rows would come
  back but their files would be gone. For a single row,
  `delete_files_of_deleted_row/1` does this for you.
  """
  def delete_files(paths) when is_list(paths) do
    # Sorting out which paths to delete happens here, right away; only
    # the slow storage requests go to the background.
    image_folders = Enum.filter(paths, fn path -> image_folder_to_delete?(path) end)

    if image_folders != [] do
      Task.Supervisor.start_child(ArtsyNeighbor.TaskSupervisor, fn ->
        delete_image_folders(image_folders)
      end)
    end

    :ok
  end

  def delete_files(path), do: delete_files([path])

  @doc """
  For a context function that deletes one photo row in a transaction:
  pass it the transaction's result. On `{:ok, row}` (the delete has
  committed) it deletes that photo's files with `delete_files/1`; an
  `{:error, reason}` means nothing was deleted, so the files stay. It
  returns the result unchanged either way, so it can sit at the end of
  a pipeline:

      product_image
      |> delete_product_image_row()
      |> Images.delete_files_of_deleted_row()
  """
  def delete_files_of_deleted_row({:ok, deleted_row} = result) do
    delete_files(deleted_row.path)
    result
  end

  def delete_files_of_deleted_row({:error, _reason} = result), do: result

  defp image_folder_to_delete?("/" <> _old_style_path), do: false

  defp image_folder_to_delete?(path) do
    if Storage.image_folder?(path) do
      true
    else
      Logger.warning("Not deleting photo files for unexpected path #{inspect(path)}")
      false
    end
  end

  # Runs in the background task. Task.async_stream runs up to
  # @delete_concurrency deletes at once; a delete that takes over a
  # minute is stopped and logged rather than holding up the rest.
  defp delete_image_folders(image_folders) do
    image_folders
    |> Task.async_stream(
      fn image_folder -> delete_image_folder(image_folder) end,
      max_concurrency: @delete_concurrency,
      timeout: 60_000,
      on_timeout: :kill_task,
      zip_input_on_exit: true
    )
    |> Enum.each(fn
      {:ok, :ok} ->
        :ok

      {:exit, {image_folder, reason}} ->
        Logger.error("Deleting photo files #{image_folder} stopped: #{inspect(reason)}")
    end)
  end

  defp delete_image_folder(image_folder) do
    case Storage.delete_prefix(image_folder) do
      :ok ->
        Logger.info("Deleted photo files #{image_folder}")

      {:error, reason} ->
        Logger.error("Deleting photo files #{image_folder} failed: #{inspect(reason)}")
    end

    :ok
  rescue
    # A crash in the storage library (e.g. a missing setting) is logged
    # like any other failure, and the other folders still get deleted.
    exception ->
      Logger.error(
        "Deleting photo files #{image_folder} crashed: " <>
          Exception.format(:error, exception, __STACKTRACE__)
      )

      :ok
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
  # cheap even for a big photo; the pixels are decoded later, in
  # make_webp_files/4 (decode_into_memory/1).
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
      {:ok, loader}
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
  # `loader` is the file format check_format/2 found, e.g. "heifload".
  #
  # Reads the upload again from its path rather than reusing the image
  # opened for the checks: from a path, libvips can shrink while
  # reading (e.g. decode a big JPEG at half size straight away), which
  # needs much less memory.
  defp make_webp_files(tmp_path, work_dir, client_name, loader) do
    source_path = Path.join(work_dir, "source.webp")

    # `thumbnail` with `resize: :down` only ever shrinks. It also:
    #   * turns the photo upright using its orientation note (EXIF),
    #   * converts colours to sRGB, the colour space browsers assume
    #     (iPhone photos are in the wider "Display P3"), so the colours
    #     still look right once the colour profile is stripped.
    result =
      with {:ok, upright} <-
             Image.thumbnail(tmp_path, @source_max_side,
               resize: :down,
               autorotate: true,
               export_icc_profile: :srgb
             ),
           {:ok, decoded} <- decode_into_memory(upright, client_name, loader),
           :ok <- write_webp(decoded, source_path, @source_quality, @source_effort) do
        make_display_sizes(decoded, work_dir)
      end

    case result do
      {:ok, display_files} ->
        {:ok, [{source_path, "source.webp", :private} | display_files]}

      # Already logged and worded by decode_into_memory/3.
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        Logger.info("Image upload #{inspect(client_name)} failed to process: #{inspect(reason)}")
        {:error, @msg_not_an_image}
    end
  end

  # libvips works "lazily": `upright` is only a recipe, and the pixels
  # are worked out when something is written. Writing four files from
  # the recipe would decode the upload four times, so `copy_memory`
  # decodes it once, into memory, and all four files are made from
  # that. It always holds 8 bits per colour (`thumbnail` converts
  # 16-bit photos, checked 2026-11-19), so it takes 3 bytes per pixel,
  # 4 with transparency: 37 MB for a 12 MP photo, at most 64 MB
  # (4096 × 4096 with transparency).
  #
  # This is where the pixels are actually decoded, so a photo that can't
  # be decoded fails here, not when opened: e.g. an iPhone HEIC photo on
  # a libvips without the HEVC decoder (the `image` library's bundled
  # libvips can open a HEIC file and read its size, but not its pixels).
  # copy_memory's error only says "Failed to memory copy image" (libvips'
  # own message goes to the terminal), so for a HEIC file we ask
  # heic_decoding_supported?/0 rather than read the message.
  # Returns {:ok, decoded} or {:error, message for the artist}.
  defp decode_into_memory(upright, client_name, loader) do
    case Vix.Vips.Image.copy_memory(upright) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        log_message =
          "Image upload #{inspect(client_name)} (#{loader}) couldn't be decoded: " <>
            inspect(reason)

        if loader == "heifload" and not heic_decoding_supported?() do
          Logger.warning(log_message <> "; this server's libvips can't decode HEIC")
          {:error, @msg_heic_unsupported}
        else
          Logger.info(log_message)
          {:error, @msg_not_an_image}
        end
    end
  end

  @doc """
  True if this server's libvips can decode iPhone (HEIC) photos. It
  decodes `priv/image_check/check.heic`, a tiny HEVC-encoded sample,
  the same check as `ArtsyNeighbor.Release.image_support/0`. Only
  asked after a HEIC photo has failed to decode, to tell the artist
  the right thing.
  """
  def heic_decoding_supported? do
    sample = Application.app_dir(:artsy_neighbor, "priv/image_check/check.heic")

    case Image.open(sample) do
      {:ok, image} -> match?({:ok, _}, Vix.Vips.Image.copy_memory(image))
      {:error, _reason} -> false
    end
  end

  # The display sizes are made from the decoded photo in memory (see
  # make_webp_files/3), which is already upright and sRGB.
  defp make_display_sizes(decoded, work_dir) do
    # The files to make: [{long_side, local_path, file_name}, ...]
    planned =
      for {name, long_side} <- @sizes do
        file_name = Atom.to_string(name) <> ".webp"
        {long_side, Path.join(work_dir, file_name), file_name}
      end

    result =
      each_until_error(planned, fn {long_side, out_path, _file_name} ->
        with {:ok, resized} <- Image.thumbnail(decoded, long_side, resize: :down) do
          write_webp(resized, out_path, @display_quality, @display_effort)
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
  # the colour profile, ...), and tells the writer to keep none either
  # (`keep: NONE`), so nothing slips through.
  #
  # Calls libvips' WebP writer directly rather than `Image.write/3`:
  # that one takes `effort` on its own 1–10 scale and converts it, so
  # WebP effort 0 can't be reached through it. `keep` needs libvips
  # 8.15 or newer (Fly's Debian has 8.16, the Mac 8.18).
  # Returns :ok or {:error, reason}.
  defp write_webp(image, path, quality, effort) do
    with {:ok, clean} <- Image.remove_metadata(image) do
      Vix.Vips.Operation.webpsave(clean, path,
        Q: quality,
        effort: effort,
        keep: [:VIPS_FOREIGN_KEEP_NONE]
      )
    end
  end

  # Writes the files to storage at the same time (see @store_concurrency).
  # Waits for all of them, even after one fails, so that none is still
  # being written when the clean-up below deletes the folder.
  #
  # The writes run as tasks under ArtsyNeighbor.TaskSupervisor, *not
  # linked* to the caller (`async_stream_nolink`). With linked tasks
  # (plain Task.async_stream), a write that raises would kill the
  # caller on the spot: the clean-up below and the removal of the work
  # folder (with its private source.webp) would never run. Unlinked, a
  # crash comes back as {:exit, reason} and is handled like any failure.
  defp store_files(files, key) do
    put_results =
      ArtsyNeighbor.TaskSupervisor
      |> Task.Supervisor.async_stream_nolink(
        files,
        fn {local_path, file_name, visibility} ->
          Storage.put(local_path, key <> "/" <> file_name, visibility)
        end,
        max_concurrency: @store_concurrency,
        # No time limit here, as when the files were written one after
        # another: the storage requests have their own.
        timeout: :infinity
      )
      |> Enum.map(fn task_result -> put_outcome(task_result) end)

    result =
      case Enum.find(put_results, fn put_result -> put_result != :ok end) do
        nil -> :ok
        {:error, reason} -> {:error, reason}
      end

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

  # What one storage task gave: :ok or {:error, reason}, whether
  # Storage.put returned an error, crashed, or returned something
  # unexpected.
  defp put_outcome({:ok, :ok}), do: :ok
  defp put_outcome({:ok, {:error, reason}}), do: {:error, reason}
  defp put_outcome({:ok, other}), do: {:error, {:unexpected_result, other}}
  defp put_outcome({:exit, reason}), do: {:error, {:crashed, reason}}

  # --- Timing log ------------------------------------------------------
  #
  # One line per stored photo, so we can see where the time goes on the
  # real server (NOTES step 2c), e.g.
  #
  #   Photo stored products/12/0b6c…: "IMG_6457.HEIC", heif 4032×3024
  #   (12.2 MP, 2.3 MB); waited 0 ms, processing 2140 ms, storing 380 ms;
  #   memory 412 MB, peak 690 MB
  #
  # "waited" is the time spent waiting for a free slot in the Limiter.
  # "processing" is checking + making the four WebP files; "storing" is
  # writing them to storage (Tigris on Fly, a folder in dev).

  defp now_ms, do: System.monotonic_time(:millisecond)

  # Runs `fun` and returns {milliseconds it took, its result}.
  defp timed(fun) do
    started_at = now_ms()
    result = fun.()
    {now_ms() - started_at, result}
  end

  defp log_timing(facts) do
    width = Image.width(facts.image)
    height = Image.height(facts.image)
    megapixels = Float.round(width * height / 1_000_000, 1)
    format = String.replace_suffix(facts.loader, "load", "")

    file_size =
      case File.stat(facts.tmp_path) do
        {:ok, stat} -> format_mb(stat.size)
        {:error, _} -> "size unknown"
      end

    Logger.info(
      "Photo stored #{facts.key}: #{inspect(facts.client_name)}, " <>
        "#{format} #{width}×#{height} (#{megapixels} MP, #{file_size}); " <>
        "waited #{facts.waited_ms} ms, processing #{facts.processing_ms} ms, " <>
        "storing #{facts.storing_ms} ms; #{memory_text()}"
    )
  end

  defp format_mb(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  # The whole server process's memory, as the operating system sees it.
  # (The BEAM's own count, :erlang.memory/0, would miss libvips, which
  # allocates its memory outside the BEAM.) Linux (the Fly server)
  # reports it in /proc/self/status:
  #   VmRSS — memory in use right now;
  #   VmHWM — the highest it has been since the server started ("high
  #           water mark"). If a photo pushes this up, that photo set a
  #           new peak. With two photos processed at once, a peak can
  #           come from both together.
  # Other systems (macOS in dev) don't have this file.
  defp memory_text do
    case File.read("/proc/self/status") do
      {:ok, status} ->
        "memory #{proc_status_mb(status, "VmRSS")}, peak #{proc_status_mb(status, "VmHWM")}"

      {:error, _} ->
        "memory not measured on this system"
    end
  end

  # Finds a line like "VmRSS:    421888 kB" and returns "412 MB".
  defp proc_status_mb(status, field) do
    case Regex.run(~r/^#{field}:\s+(\d+) kB/m, status) do
      [_line, kilobytes] -> "#{div(String.to_integer(kilobytes), 1024)} MB"
      nil -> "?"
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
