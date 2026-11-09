# Can this machine's libvips decode HEIC photos? (Homebrew's can; the
# `image` library's bundled one can't — see image_setup_test.exs.)
# Tests tagged :heic need it, tests tagged :no_heic need it missing,
# so exactly one of the two kinds is skipped.
heic_fixture = Path.expand("support/images/cat-sculpture.heic", __DIR__)

# Without this check, a missing fixture would look like "no HEIC
# support" and quietly skip the HEIC tests.
unless File.exists?(heic_fixture) do
  raise "HEIC test photo missing: #{heic_fixture}"
end

heic_supported? =
  case Image.open(heic_fixture) do
    {:ok, image} -> match?({:ok, _}, Image.write(image, :memory, suffix: ".webp"))
    {:error, _} -> false
  end

if heic_supported? do
  ExUnit.configure(exclude: [:no_heic])
else
  ExUnit.configure(exclude: [:heic])
end

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(ArtsyNeighbor.Repo, :manual)
