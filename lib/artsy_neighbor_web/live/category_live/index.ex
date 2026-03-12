defmodule ArtsyNeighborWeb.CategoryLive.Index do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Categories
  import ArtsyNeighborWeb.CustomComponents, only: [ category_card: 1, back: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>
      <.header>
        Product Categories

      </.header>




      <div class="grid grid-cols-1 gap-8">
      <%!-- Categories (3 images in a row) --%>
      <section>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">

        <.category_card :for={category <- @categories} category={category} />

        </div>


      </section>
    </div>
    </Layouts.artsy_main>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Categories")
     |> assign(:categories, list_categories())}
  end



  defp list_categories() do
    Categories.list_categories()
  end
end
