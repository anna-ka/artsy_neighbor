defmodule ArtsyNeighborWeb.AdminProductLive.Index do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Categories

  import ArtsyNeighborWeb.CustomComponents,
    only: [button_artsy: 1, form_table: 1, back: 1, status_actions: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    categories =
      Categories.list_categories_all_status() |> Enum.map(fn cat -> {cat.name, cat.id} end)

    socket =
      socket
      |> assign(:page_title, "Admin - Products")
      |> assign(:categories, categories)
      |> assign(:form, to_form(params))
      |> stream(:products, Products.filter_products_all_status(params), reset: true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    params =
      params
      |> Map.take(["search", "category_id", "artist", "sort_by"])
      |> Map.reject(fn {_k, v} -> v in [nil, ""] end)

    {:noreply, push_patch(socket, to: ~p"/admin/products?#{params}")}
  end

  # Soft removal — sets status to :archived, reversible by editing the
  # product. Mirrors AdminArtistLive.Index's "mark removed" vs "delete" split.
  @impl true
  def handle_event("archive", %{"id" => id}, socket) do
    product = Products.get_product_with_associations!(id)
    {:ok, updated_product} = Products.soft_delete_product(product)

    message = "Product \"#{product.title}\" has been archived."

    socket =
      socket
      |> stream_insert(:products, updated_product)
      |> put_flash(:info, message)

    {:noreply, socket}
  end

  # Reverses "archive" — see Products.restore_product/1. Lands on
  # :unavailable, not :available: there is no "mark available" action yet
  # (see that function's own doc comment), so restoring here is a real but
  # incomplete step, not a full undo of "archive".
  #
  # restore_product/1 can return {:error, :artist_not_active} (the owning
  # artist isn't currently :active — only_available/1 would hide the
  # product regardless, so restoring it would leave a product with an
  # unreachable seller once "mark available" exists) or
  # {:error, :category_missing} (its category was deleted out from under
  # it — can't actually happen from this view today, since
  # filter_products_all_status/1 inner-joins :category, but the guard
  # stays defensive) in addition to a changeset error — handled below with
  # a flash for each rather than a MatchError.
  @impl true
  def handle_event("restore", %{"id" => id}, socket) do
    product = Products.get_product_with_associations!(id)

    socket =
      case Products.restore_product(product) do
        {:ok, updated_product} ->
          message =
            "Product \"#{product.title}\" has been restored to unavailable — marking it available again isn't built yet."

          socket
          |> stream_insert(:products, updated_product)
          |> put_flash(:info, message)

        {:error, :artist_not_active} ->
          put_flash(
            socket,
            :error,
            "Could not restore \"#{product.title}\" — its artist isn't currently active."
          )

        {:error, :category_missing} ->
          put_flash(
            socket,
            :error,
            "Could not restore \"#{product.title}\" — its category no longer exists."
          )

        {:error, _reason} ->
          put_flash(
            socket,
            :error,
            "Could not restore \"#{product.title}\". Please try again."
          )
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    product = Products.get_product!(id)

    socket =
      case Products.hard_delete_product(product) do
        {:ok, _} ->
          socket
          |> stream_delete(:products, product)
          |> put_flash(:info, "Product \"#{product.title}\" deleted successfully.")

        {:error, _reason} ->
          put_flash(
            socket,
            :error,
            "Could not delete \"#{product.title}\" — it may still have reviews attached. Try archiving it instead."
          )
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
          {@page_title}
          <:actions>
            <.button_artsy navigate={~p"/admin/products/new"} variant="secondary">
              New Product
            </.button_artsy>
          </:actions>
        </.header>

        <section class="my-6">
          <.filter_form form={@form} categories={@categories} />
        </section>

        <div class="overflow-x-auto">
          <.form_table id="admin-products-table" rows={@streams.products}>
            <%!-- Image --%>
            <:col :let={{_dom_id, product}} label="Image" col_class="w-20">
              <div class="avatar">
                <div class="mask mask-squircle h-12 w-12">
                  <% img = List.first(product.product_images) %>
                  <img
                    src={if img, do: img.path, else: "/images/avatar-placeholder.png"}
                    alt={product.title}
                  />
                </div>
              </div>
            </:col>

            <%!-- Title --%>
            <:col :let={{_dom_id, product}} label="Title" col_class="w-40">
              {product.title}
            </:col>

            <%!-- Artist --%>
            <:col :let={{_dom_id, product}} label="Artist" col_class="w-32">
              {product.artist.nickname}
            </:col>

            <%!-- Category --%>
            <:col :let={{_dom_id, product}} label="Category" col_class="w-32">
              {product.category.name}
            </:col>

            <%!-- Price --%>
            <:col :let={{_dom_id, product}} label="Price" col_class="w-24">
              ${product.price}
            </:col>

            <%!-- Status --%>
            <:col :let={{_dom_id, product}} label="Status" col_class="w-24">
              {product.status}
            </:col>

            <%!-- Actions --%>
            <:col :let={{_dom_id, product}} label="Actions" col_class="w-56">
              <.status_actions
                id={product.id}
                view_path={~p"/admin/products/#{product}"}
                edit_path={~p"/admin/products/#{product}/edit"}
                show_restore={product.status != :available}
                restore_confirm={"Restore \"#{product.title}\"? Its status will change to unavailable — marking it available again isn't built yet, so it still won't be publicly purchasable after this."}
                soft_delete_event="archive"
                soft_delete_label="archive"
                soft_delete_confirm={"Archive \"#{product.title}\"? It will be hidden from the public site. This can be reversed using the restore action, though restoring only brings it back to unavailable — a separate step to mark it available again isn't built yet."}
                hard_delete_confirm={"Permanently delete \"#{product.title}\"? This cannot be undone."}
              />
            </:col>
          </.form_table>
        </div>
      </div>
    </Layouts.artsy_wide>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :categories, :list, required: true

  def filter_form(assigns) do
    ~H"""
    <.form for={@form} id="filter-form" phx-change="filter" phx-submit="filter">
      <div class="flex flex-wrap gap-4 items-end">
        <%!-- Search --%>
        <div class="flex-1 min-w-48">
          <.input
            field={@form[:search]}
            type="text"
            label="Search"
            placeholder="Search products..."
            autocomplete="off"
            phx-debounce="500"
          />
        </div>

        <%!-- Filter by Category --%>
        <div class="min-w-48">
          <.input
            field={@form[:category_id]}
            type="select"
            label="Category"
            prompt="All categories"
            options={@categories}
          />
        </div>

        <%!-- Filter by Artist --%>
        <div class="min-w-48">
          <.input
            field={@form[:artist]}
            type="text"
            label="Artist"
            autocomplete="off"
            phx-debounce="500"
          />
        </div>

        <%!-- Sort By --%>
        <div class="min-w-48">
          <.input
            field={@form[:sort_by]}
            type="select"
            label="Sort by"
            prompt="Default"
            options={[
              {"Price: Low to High", "price_asc"},
              {"Price: High to Low", "price_desc"},
              {"Artist", "artist"},
              {"Category", "category"}
            ]}
          />
        </div>

        <%!-- Reset --%>
        <div>
          <.link patch={~p"/admin/products"} class="btn btn-ghost">Clear</.link>
        </div>
      </div>
    </.form>
    """
  end
end
