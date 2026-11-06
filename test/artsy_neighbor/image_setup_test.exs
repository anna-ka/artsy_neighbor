defmodule ArtsyNeighbor.ImageSetupTest do
  @moduledoc """
  Guards the machine setup, not our own code: checks that the `vix`
  library was compiled against Homebrew's libvips (which can decode
  iPhone HEIC photos) rather than its own bundled copy (which can't).

  If this fails, `VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS` was
  probably not set when `vix` was compiled. Fix (in a terminal that has
  the variable, see `~/.zshrc` and NOTES.md):

      mix deps.clean vix && mix deps.compile vix

  Note: libvips opens files lazily. The bundled libvips happily *opens*
  a HEIC file (it can read the header) and only fails when it decodes
  the pixels, so this test has to force a full decode.
  """
  use ExUnit.Case, async: true

  @heic_fixture "test/support/images/cat-sculpture.heic"

  test "libvips can decode the pixels of an HEVC-encoded HEIC photo" do
    {:ok, image} = Image.open(@heic_fixture)

    # Writing to memory forces libvips to decode every pixel.
    case Image.write(image, :memory, suffix: ".webp") do
      {:ok, webp_bytes} ->
        assert byte_size(webp_bytes) > 0

      {:error, error} ->
        flunk("""
        libvips could not decode a HEIC photo: #{inspect(error)}

        vix was most likely compiled against its own bundled libvips.
        In a terminal where VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS
        is set, run: mix deps.clean vix && mix deps.compile vix
        """)
    end
  end
end
