defmodule ArtsyNeighborWeb.AdminCategoryLive.Index do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Admin.AdminCategories
  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, form_table: 1, back: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin - Categories")
     |> stream(:categories, AdminCategories.list_categories())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    category = AdminCategories.get_category!(id)
    {:ok, _} = AdminCategories.delete_category(category)

    message = "Category #{category.name} deleted successfully."

    socket =
      socket
      |> stream_delete(:categories, category)
      |> put_flash(:info, message)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_wide flash={@flash} variant="admin">
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

            <%!-- Actions --%>
            <:col :let={{_dom_id, category}} label="Actions" col_class="w-36">
              <div class="flex gap-2">
                <.link navigate={~p"/admin/categories/#{category}"}>
                  <button class="btn btn-ghost btn-xs">view</button>
                </.link>
                <.link navigate={~p"/admin/categories/#{category}/edit"}>
                  <button class="btn btn-ghost btn-xs">edit</button>
                </.link>
                <.link
                  phx-click="delete"
                  phx-value-id={category.id}
                  data-confirm={"Are you sure you want to delete category #{category.name}?"}>
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
end
