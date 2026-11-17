# Wipes the DEV database and fills it with sample data. Run it with:
#
#     mix run priv/repo/seeds.exs
#
# (`mix setup` and `mix ecto.setup` run it too.) It DELETES the data in
# every table first, and the photo files of the deleted photos, so never
# run it on a database whose data you want to keep. It only runs in dev.
#
# The sample data itself (categories, artists, works) is in
# priv/repo/sample_data/ and is added by ArtsyNeighbor.SampleData, the
# same way the Fly preview gets it (ArtsyNeighbor.Release.add_sample_data/0).
# All its photos go through Images.process_upload/3, so this takes a
# minute or two.

alias ArtsyNeighbor.Repo
alias ArtsyNeighbor.Accounts.User
alias ArtsyNeighbor.Accounts.Admin
alias ArtsyNeighbor.Artists.Artist
alias ArtsyNeighbor.Categories.Category
alias ArtsyNeighbor.Products.Product
alias ArtsyNeighbor.Orders.OrderItem
alias ArtsyNeighbor.Orders.Order
alias ArtsyNeighbor.Conversations.ConversationEvent
alias ArtsyNeighbor.Conversations.Conversation
alias ArtsyNeighbor.Artists.ArtistImage
alias ArtsyNeighbor.Products.ProductImage
alias ArtsyNeighbor.Storage

# Everything below is for the developer's Mac only: it wipes the
# database, and the sample accounts it makes share a published password.
if Mix.env() != :dev do
  raise "seeds.exs only runs in dev (MIX_ENV=dev), not in #{Mix.env()}."
end

# The admin account's email and password, from .env (read before
# anything is deleted, so a missing one stops it with nothing changed).
admin_email =
  System.get_env("SEED_ADMIN_EMAIL") ||
    raise "SEED_ADMIN_EMAIL is not set. Add it to your .env file."

admin_password =
  System.get_env("SEED_ADMIN_PASSWORD") ||
    raise "SEED_ADMIN_PASSWORD is not set. Add it to your .env file."

# ============================================================
# Cleanup (most-dependent tables first)
# ============================================================

# The photo rows go with their artists and products below (the
# database deletes them along), so note their storage keys first, to
# delete their files afterwards. Old-style paths (starting with "/")
# are site images, not stored photos: those are left alone.
stored_photo_keys =
  Repo.all(ArtistImage)
  |> Enum.concat(Repo.all(ProductImage))
  |> Enum.map(fn image -> image.path end)
  |> Enum.filter(fn path -> Storage.image_folder?(path) end)

Repo.delete_all(OrderItem)
Repo.delete_all(ConversationEvent)
Repo.delete_all(Order)
Repo.delete_all(Conversation)
Repo.delete_all(Product)
Repo.delete_all(Artist)
Repo.delete_all(Category)
Repo.delete_all(Admin)
Repo.delete_all(User)

# Deleted one by one, right here, rather than with Images.delete_files/1,
# which works in the background: a script can end before that is done.
for key <- stored_photo_keys do
  Storage.delete_prefix(key)
end

IO.puts("Deleted all data, and the files of #{length(stored_photo_keys)} stored photos")

# ============================================================
# Admin user account (reads its email and password from .env)
# ============================================================

# Made before the sample data, so that SampleData links the developer's
# studio (annas_studio.exs) to this account.
anna_user =
  %User{}
  |> User.registration_changeset(%{email: admin_email, username: "annak"})
  |> User.password_changeset(%{password: admin_password})
  |> User.confirm_changeset()
  |> Repo.insert!()

# Grant admin privileges
%Admin{}
|> Ecto.Changeset.cast(%{user_id: anna_user.id}, [:user_id])
|> Ecto.Changeset.validate_required([:user_id])
|> Repo.insert!()

IO.puts("Seeded admin user account successfully!")

# ============================================================
# Sample data
# ============================================================

ArtsyNeighbor.SampleData.add_all()
