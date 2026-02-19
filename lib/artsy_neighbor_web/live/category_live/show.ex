defmodule ArtsyNeighborWeb.CategoryLive.Show do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Categories

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>
      <div class="mb-6">
        <.link navigate={~p"/categories"} class="text-sm hover:underline">
          ← All categories
        </.link>
      </div>

      <%!-- Category header: two-column layout --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-8 mb-12">
        <div class="rounded-xl overflow-hidden bg-gray-200">
          <img src={@category.main_img} alt={@category.name} class="w-full h-full object-contain" />
        </div>
        <div class="flex flex-col justify-center">
          <h1 class="text-4xl font-bold mb-4">{@category.name}</h1>
          <p class="text-lg">{@category.description}</p>
        </div>
      </div>

      <%!-- Products section (coming soon) --%>
      <section>
        <h2 class="text-2xl font-bold mb-6">Products in this category</h2>
        <p class="text-gray-500">Products coming soon.</p>
      </section>
    </Layouts.artsy_main>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    category = Categories.get_category!(id)

    {:ok,
     socket
     |> assign(:page_title, category.name)
     |> assign(:category, category)}
  end
end
