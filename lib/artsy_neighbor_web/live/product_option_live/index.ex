defmodule ArtsyNeighborWeb.ProductOptionLive.Index do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Product options
        <:actions>
          <.button variant="primary" navigate={~p"/product_options/new"}>
            <.icon name="hero-plus" /> New Product option
          </.button>
        </:actions>
      </.header>

      <.table
        id="product_options"
        rows={@streams.product_options}
        row_click={fn {_id, product_option} -> JS.navigate(~p"/product_options/#{product_option}") end}
      >
        <:col :let={{_id, product_option}} label="Name">{product_option.name}</:col>
        <:col :let={{_id, product_option}} label="Descr">{product_option.descr}</:col>
        <:col :let={{_id, product_option}} label="Values">{product_option.values}</:col>
        <:action :let={{_id, product_option}}>
          <div class="sr-only">
            <.link navigate={~p"/product_options/#{product_option}"}>Show</.link>
          </div>
          <.link navigate={~p"/product_options/#{product_option}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, product_option}}>
          <.link
            phx-click={JS.push("delete", value: %{id: product_option.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Product options")
     |> stream(:product_options, list_product_options())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    product_option = Products.get_product_option!(id)
    {:ok, _} = Products.delete_product_option(product_option)

    {:noreply, stream_delete(socket, :product_options, product_option)}
  end

  defp list_product_options() do
    Products.list_product_options()
  end
end
