defmodule ArtsyNeighborWeb.AdminCategoryLive.Index do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Admin.AdminCategories

  import ArtsyNeighborWeb.CustomComponents,
    only: [button_artsy: 1, form_table: 1, back: 1, status_actions: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin - Categories")
     |> stream(:categories, AdminCategories.list_categories_all_status())}
  end

  # Soft removal — sets status to :archived, reversible via "restore".
  # Mirrors AdminProductLive.Index's "archive" vs "delete" split.
  #
  # soft_delete_category/1 can return {:error, :has_active_products} (the
  # category still has :available products — see
  # Categories.has_active_products?/1) in addition to a changeset error —
  # handled below with a flash rather than a MatchError.
  @impl true
  def handle_event("archive", %{"id" => id}, socket) do
    category = AdminCategories.get_category!(id)

    socket =
      case AdminCategories.soft_delete_category(category) do
        {:ok, updated_category} ->
          message = "Category #{category.name} has been archived."

          socket
          |> stream_insert(:categories, updated_category)
          |> put_flash(:info, message)

        {:error, :has_active_products} ->
          put_flash(
            socket,
            :error,
            "Could not archive #{category.name} — it still has available products. Move or archive them first."
          )

        {:error, _reason} ->
          put_flash(socket, :error, "Could not archive #{category.name}. Please try again.")
      end

    {:noreply, socket}
  end

  # Reverses "archive" — see AdminCategories.restore_category/1. Lands
  # straight on :active: unlike Artist/Product, Category has no
  # intermediate "reactivate separately" step, since it carries no
  # trust/vetting semantics of its own.
  #
  # restore_category/1 can return {:error, :already_active} (stale
  # page/double-click on a category someone else already restored) in
  # addition to a changeset error — handled below with a flash rather than
  # a MatchError.
  @impl true
  def handle_event("restore", %{"id" => id}, socket) do
    category = AdminCategories.get_category!(id)

    socket =
      case AdminCategories.restore_category(category) do
        {:ok, updated_category} ->
          message = "Category #{category.name} has been restored."

          socket
          |> stream_insert(:categories, updated_category)
          |> put_flash(:info, message)

        {:error, :already_active} ->
          put_flash(socket, :info, "#{category.name} is already active — nothing to restore.")

        {:error, _reason} ->
          put_flash(socket, :error, "Could not restore #{category.name}. Please try again.")
      end

    {:noreply, socket}
  end

  # Permanently deletes a category via AdminCategories.hard_delete_category/1
  # — a hard delete, unlike "archive" above. products.category_id is
  # on_delete: :nilify_all, so any product using this category is not
  # deleted, just orphaned from it. Meant for admin/testing cleanup, not
  # the normal removal action — that's "archive", which is fully
  # reversible. The confirm dialog spells this out before the event fires.
  #
  # hard_delete_category/1 can return {:error, :has_active_products} (same
  # guard as soft_delete_category/1 — see
  # Categories.has_active_products?/1) in addition to a changeset error —
  # handled below with a flash rather than a MatchError.
  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    category = AdminCategories.get_category!(id)

    socket =
      case AdminCategories.hard_delete_category(category) do
        {:ok, _deleted} ->
          message = "Category #{category.name} deleted successfully."

          socket
          |> stream_delete(:categories, category)
          |> put_flash(:info, message)

        {:error, :has_active_products} ->
          put_flash(
            socket,
            :error,
            "Could not delete #{category.name} — it still has available products. Move or archive them first."
          )

        {:error, _reason} ->
          put_flash(socket, :error, "Could not delete #{category.name}. Please try again.")
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_wide flash={@flash} variant="admin" nav_categories={@nav_categories}>
      <div class="admin-index">

       <div>
        <.back navigate={~p"/admin"}>
              Admin Dashboard
        </.back>
      </div>

        <.header>
          <%= @page_title %>
          <:actions>
            <.button_artsy navigate={~p"/admin/categories/new"} variant="secondary">
              New Category
            </.button_artsy>
          </:actions>
        </.header>

        <div class="overflow-x-auto">
          <.form_table id="admin-categories-table" rows={@streams.categories}>

            <%!-- Image --%>
            <:col :let={{_dom_id, category}} label="Image" col_class="w-20">
              <div class="avatar">
                <div class="mask mask-squircle h-12 w-12 bg-gray-200">
                  <img src={category.main_img} alt={category.name} />
                </div>
              </div>
            </:col>

            <%!-- Name --%>
            <:col :let={{_dom_id, category}} label="Name" col_class="w-32">
              <%= category.name %>
            </:col>

            <%!-- Slug --%>
            <:col :let={{_dom_id, category}} label="Slug" col_class="w-32">
              <span class="badge badge-outline"><%= category.slug %></span>
            </:col>

            <%!-- Description (truncated) --%>
            <:col :let={{_dom_id, category}} label="Description" col_class="w-64">
              <%= String.slice(category.description, 0, 60) %><%= if String.length(category.description) > 60, do: "..." %>
            </:col>

            <%!-- Status --%>
            <:col :let={{_dom_id, category}} label="Status" col_class="w-24">
              {category.status}
            </:col>

            <%!-- Actions --%>
            <:col :let={{_dom_id, category}} label="Actions" col_class="w-56">
              <.status_actions
                id={category.id}
                view_path={~p"/admin/categories/#{category}"}
                edit_path={~p"/admin/categories/#{category}/edit"}
                show_restore={category.status != :active}
                restore_confirm={"Restore #{category.name}? It will become visible to the public again."}
                soft_delete_event="archive"
                soft_delete_label="archive"
                soft_delete_confirm={"Archive #{category.name}? It will be hidden from the public site. This can be reversed using the restore action."}
                hard_delete_confirm={"Permanently delete #{category.name}? Any products using it will be unassigned from it, not deleted. This cannot be undone."}
              />
            </:col>

          </.form_table>
        </div>
      </div>
    </Layouts.artsy_wide>
    """
  end
end
