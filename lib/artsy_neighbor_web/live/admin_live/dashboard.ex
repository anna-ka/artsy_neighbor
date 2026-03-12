defmodule ArtsyNeighborWeb.AdminLive.Dashboard do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Categories

  def mount(_params, _session, socket) do
    artist_count  = length(Artists.list_artists())
    product_count = length(Products.list_products())
    category_count = length(Categories.list_categories())

    {:ok,
     assign(socket,
       page_title: "Admin Dashboard",
       artist_count: artist_count,
       product_count: product_count,
       category_count: category_count
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash} variant="admin">
      <div class="space-y-10">

        <%!-- Header --%>
        <div>
          <h1 class="text-3xl font-bold">Admin Dashboard</h1>
          <p class="text-base-content/60 mt-1">Manage artists, products, and categories.</p>
        </div>

        <%!-- Stats row --%>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">

          <div class="stat bg-base-200 rounded-box">
            <div class="stat-title">Artists</div>
            <div class="stat-value">{@artist_count}</div>
            <div class="stat-actions">
              <.link navigate={~p"/admin/artists"} class="btn btn-sm btn-ghost">Manage →</.link>
            </div>
          </div>

          <div class="stat bg-base-200 rounded-box">
            <div class="stat-title">Products</div>
            <div class="stat-value">{@product_count}</div>
            <div class="stat-actions">
              <.link navigate={~p"/admin/products"} class="btn btn-sm btn-ghost">Manage →</.link>
            </div>
          </div>

          <div class="stat bg-base-200 rounded-box">
            <div class="stat-title">Categories</div>
            <div class="stat-value">{@category_count}</div>
            <div class="stat-actions">
              <.link navigate={~p"/admin/categories"} class="btn btn-sm btn-ghost">Manage →</.link>
            </div>
          </div>

        </div>

        <%!-- Quick links --%>
        <div>
          <h2 class="text-xl font-semibold mb-4">Quick actions</h2>
          <div class="flex flex-wrap gap-3">
            <.link navigate={~p"/admin/artists/new"} class="btn btn-outline btn-sm">
              + New Artist
            </.link>
            <.link navigate={~p"/admin/products/new"} class="btn btn-outline btn-sm">
              + New Product
            </.link>
            <.link navigate={~p"/admin/categories/new"} class="btn btn-outline btn-sm">
              + New Category
            </.link>
          </div>
        </div>

      </div>
    </Layouts.artsy_main>
    """
  end
end
