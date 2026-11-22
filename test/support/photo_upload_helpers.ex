defmodule ArtsyNeighborWeb.PhotoUploadHelpers do
  @moduledoc """
  Photos for LiveView upload tests, in the form `file_input/4` takes.

  All are made from a site image (never from real phone photos, which
  carry GPS locations). Processing really happens: the files go
  through `ArtsyNeighbor.Images` into the test storage folder
  (`config/test.exs`).
  """

  import Phoenix.LiveViewTest

  # file_input/4 is a macro that needs to know the endpoint.
  @endpoint ArtsyNeighborWeb.Endpoint

  # 1487 × 998 pixels: big enough to be accepted.
  @site_image "priv/static/images/cat-sculpture.jpg"
  # 1000 × 671, HEVC-encoded, no GPS.
  @heic_fixture "test/support/images/cat-sculpture.heic"

  @doc "A photo that will be accepted."
  def good_photo(name \\ "cat.jpg") do
    %{name: name, content: File.read!(@site_image), type: "image/jpeg"}
  end

  @doc "A photo under 800px on the long side, which processing refuses."
  def small_photo(name \\ "small.jpg") do
    image = @site_image |> Image.open!() |> Image.thumbnail!(400)
    content = Image.write!(image, :memory, suffix: ".jpg")
    %{name: name, content: content, type: "image/jpeg"}
  end

  @doc """
  An AVIF photo (1487 × 998). AVIF is read by the same libvips loader as
  HEIC (`heifload`), so with a lowered `big_photo_pixels` setting it
  counts as a big photo, without a big file in the tests. Making it
  needs libheif, so tests using it need the `:heic` tag.
  """
  def avif_photo(name \\ "photo.avif") do
    content = @site_image |> Image.open!() |> Image.write!(:memory, suffix: ".avif")
    %{name: name, content: content, type: "image/avif"}
  end

  @doc """
  A moving image: a WebP with two pictures (1487 × 998 each), the
  second the first in negative.
  """
  def moving_webp_photo(name \\ "moving.webp") do
    %{name: name, content: moving_webp(), type: "image/webp"}
  end

  @doc "The bytes of the moving WebP of `moving_webp_photo/1`."
  def moving_webp do
    frame = Image.open!(@site_image)
    {:ok, negative} = Vix.Vips.Operation.invert(frame)
    {:ok, negative} = Vix.Vips.Operation.cast(negative, :VIPS_FORMAT_UCHAR)
    # The two pictures one above the other; "page-height" tells libvips
    # where one ends and the next begins.
    {:ok, stacked} = Vix.Vips.Operation.arrayjoin([frame, negative], across: 1)

    {:ok, moving} =
      Vix.Vips.Image.mutate(stacked, fn mutable ->
        :ok = Vix.Vips.MutableImage.set(mutable, "page-height", :gint, Image.height(frame))
        :ok = Vix.Vips.MutableImage.set(mutable, "delay", :VipsArrayInt, [500, 500])
      end)

    {:ok, bytes} = Vix.Vips.Image.write_to_buffer(moving, ".webp")
    bytes
  end

  @doc "An iPhone-style HEIC photo (tests using it need the `:heic` tag)."
  def heic_photo(name \\ "IMG_0001.HEIC") do
    %{name: name, content: File.read!(@heic_fixture), type: "image/heic"}
  end

  @doc """
  Picks `photos` in the upload `upload_name` of the form `form_selector`
  and finishes sending each one to the server, like the browser does.
  """
  def pick_photos(view, form_selector, upload_name, photos) do
    input = file_input(view, form_selector, upload_name, photos)

    for photo <- photos do
      render_upload(input, photo.name)
    end

    input
  end

  @doc """
  Waits until the page is done with its photos: none is still being
  checked ("Checking the photo…" or, for a big photo, "Large photo…";
  both are marked `data-photo-checking`) and no save is still storing
  them ("Saving your photos…"). Returns the page's HTML.

  (`render_async/2` alone isn't enough: it waits only for the background
  work running at the moment, and checking one photo starts the next,
  or the storing of a waiting save.)
  """
  def wait_for_photo_work(view, timeout_ms \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_until_done(view, deadline)
  end

  defp wait_until_done(view, deadline) do
    time_left = deadline - System.monotonic_time(:millisecond)

    if time_left <= 0 do
      ExUnit.Assertions.flunk("The page was still busy with its photos.")
    end

    # render_async raises if the work running now doesn't finish in time;
    # say what that means here instead of its own general message.
    html =
      try do
        render_async(view, time_left)
      rescue
        error ->
          ExUnit.Assertions.flunk(
            "The page was still busy with its photos: " <> Exception.message(error)
          )
      end

    # Decided from this same `html`, the one returned: a second look at
    # the page could already see the work done and return this older
    # page.
    busy? = html =~ "data-photo-checking" or html =~ ~s(id="saving-photos")

    if busy? do
      # Nothing may be running at this very moment (the next step starts
      # when LiveView handles the last one's result): look again shortly.
      Process.sleep(20)
      wait_until_done(view, deadline)
    else
      html
    end
  end
end
