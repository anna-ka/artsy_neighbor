defmodule ArtsyNeighborWeb.AdminProductLive.Index do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Categories
  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, form_table: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    categories = Categories.list_categories() |> Enum.map(fn cat -> {cat.name, cat.id} end)

    socket =
      socket
      |> assign(:page_title, "Admin - Products")
      |> assign(:categories, categories)
      |> assign(:form, to_form(params))
      |> stream(:products, Products.filter_products(params), reset: true)

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

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    product = Products.get_product!(id)
    {:ok, _} = Products.delete_product(product)

    message = "Product \"#{product.title}\" deleted successfully."

    socket =
      socket
      |> stream_delete(:products, product)
      |> put_flash(:info, message)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_wide flash={@flash}>
      <div class="admin-index">

        <.header>
          <%= @page_title %>
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
                    alt={product.title} />
                </div>
              </div>
            </:col>

            <%!-- Title --%>
            <:col :let={{_dom_id, product}} label="Title" col_class="w-40">
              <%= product.title %>
            </:col>

            <%!-- Artist --%>
            <:col :let={{_dom_id, product}} label="Artist" col_class="w-32">
              <%= product.artist.nickname %>
            </:col>

            <%!-- Category --%>
            <:col :let={{_dom_id, product}} label="Category" col_class="w-32">
              <%= product.category.name %>
            </:col>

            <%!-- Price --%>
            <:col :let={{_dom_id, product}} label="Price" col_class="w-24">
              $<%= product.price %>
            </:col>

            <%!-- Actions --%>
            <:col :let={{_dom_id, product}} label="Actions" col_class="w-36">
              <div class="flex gap-2">
                <.link navigate={~p"/admin/products/#{product}"}>
                  <button class="btn btn-ghost btn-xs">view</button>
                </.link>
                <.link navigate={~p"/admin/products/#{product}/edit"}>
                  <button class="btn btn-ghost btn-xs">edit</button>
                </.link>
                <.link
                  phx-click="delete"
                  phx-value-id={product.id}
                  data-confirm={"Are you sure you want to delete \"#{product.title}\"?"}>
                  <button class="btn btn-ghost btn-xs text-error">delete</button>
                </.link>
              </div>
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
            phx-debounce="500" />
        </div>

        <%!-- Filter by Category --%>
        <div class="min-w-48">
          <.input
            field={@form[:category_id]}
            type="select"
            label="Category"
            prompt="All categories"
            options={@categories} />
        </div>

        <%!-- Filter by Artist --%>
        <div class="min-w-48">
          <.input
            field={@form[:artist]}
            type="text"
            label="Artist"
            autocomplete="off"
            phx-debounce="500" />
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
            ]} />
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
