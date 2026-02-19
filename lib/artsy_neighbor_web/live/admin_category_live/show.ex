defmodule ArtsyNeighborWeb.AdminCategoryLive.Show do
  use ArtsyNeighborWeb, :live_view
  alias ArtsyNeighbor.Admin.AdminCategories
  import ArtsyNeighborWeb.CustomComponents, only: [category_card: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>
      <.header>
        Category {@category.id}
        <:subtitle>This is a category record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/admin/categories"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/admin/categories/#{@category}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit category
          </.button>
        </:actions>
      </.header>

      <div class="flex justify-center my-6">
        <div class="w-1/3">
          <.category_card category={@category} />
        </div>
      </div>

      <.list>
        <:item title="Name">{@category.name}</:item>
        <:item title="Description">{@category.description}</:item>
        <:item title="Main img">{@category.main_img}</:item>
        <:item title="Slug">{@category.slug}</:item>
      </.list>
    </Layouts.artsy_main>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Category")
     |> assign(:category, AdminCategories.get_category!(id))}
  end
end
