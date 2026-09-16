defmodule ArtsyNeighbor.Repo.Migrations.CascadeArtistDeleteFks do
  use Ecto.Migration

  @moduledoc """
  Switches the FKs that Artists.delete_artist/1 has to manually clean up
  today to on_delete: :delete_all, so a plain Repo.delete(artist) cascades
  through orders, order items, conversations, conversation events, and the
  three review tables on its own.

  Not covered here: `flags.subject_id` is a polymorphic reference (no real
  FK possible — it can point at an artist or at any of three review tables
  depending on subject_type), so it still needs an explicit cleanup step in
  delete_artist/1.

  Also not covered: orders.conversation_id and order_items.product_id are
  left as-is. Every order belonging to this artist is removed via
  orders.artist_id below, and every order_item belonging to this artist is
  removed via order_items.order_id below — both are sufficient on their own
  given the existing invariant that an order/order_item never points at a
  conversation/product belonging to a different artist than the order
  itself. Changing those two as well would also make delete_conversation_dev/1
  (a dev-only helper, see conversations.ex) silently cascade-delete orders,
  which is out of scope for this migration.
  """

  def change do
    alter table(:orders) do
      modify :artist_id, references(:artists, on_delete: :delete_all),
        from: references(:artists, on_delete: :nothing)
    end

    alter table(:conversations) do
      modify :artist_id, references(:artists, on_delete: :delete_all),
        from: references(:artists, on_delete: :nothing)
    end

    alter table(:conversation_events) do
      modify :conversation_id, references(:conversations, on_delete: :delete_all),
        from: references(:conversations, on_delete: :nothing)

      modify :order_id, references(:orders, on_delete: :delete_all),
        from: references(:orders, on_delete: :nothing)
    end

    alter table(:order_items) do
      modify :order_id, references(:orders, on_delete: :delete_all),
        from: references(:orders, on_delete: :nothing)
    end

    alter table(:products) do
      modify :artist_id, references(:artists, on_delete: :delete_all),
        from: references(:artists, on_delete: :nilify_all)
    end

    alter table(:vendors_reviewed) do
      modify :order_id, references(:orders, on_delete: :delete_all),
        from: references(:orders, on_delete: :restrict)

      modify :artist_id, references(:artists, on_delete: :delete_all),
        from: references(:artists, on_delete: :restrict)
    end

    alter table(:buyers_reviewed) do
      modify :order_id, references(:orders, on_delete: :delete_all),
        from: references(:orders, on_delete: :restrict)
    end

    alter table(:product_reviews) do
      modify :order_id, references(:orders, on_delete: :delete_all),
        from: references(:orders, on_delete: :restrict)

      modify :product_id, references(:products, on_delete: :delete_all),
        from: references(:products, on_delete: :restrict)
    end
  end
end
