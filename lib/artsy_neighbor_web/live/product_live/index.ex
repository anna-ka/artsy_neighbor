 defmodule ArtsyNeighborWeb.ProductLive.Index do

  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  import ArtsyNeighborWeb.CustomComponents, only: [product_card: 1]

  #mount
  def mount(_params, _session, socket) do

    {:ok, socket}
  end


  def handle_params(params, _uri, socket) do
    categories = ArtsyNeighbor.Categories.list_categories() |> Enum.map(fn cat -> {cat.name, cat.id} end)

    socket =
      socket
      |> stream(:products, Products.filter_products(params), reset: true)
      |> assign(categories: categories)
      |> assign(form: to_form(params))
      |> assign(from_category: Map.has_key?(params, "category_id"))

    {:noreply, socket}
  end

 def render(assigns) do
   ~H"""
    <Layouts.artsy_main flash={@flash}>

     <section>
      <.link :if={@from_category} navigate={~p"/categories"} class="btn btn-ghost btn-sm mb-4">
        <.icon name="hero-arrow-left" class="size-4" /> Back to Categories
      </.link>
      <h1 class="text-4xl font-bold mt-6 text-black">List of products</h1>
    </section>

    <section class="my-6">
      <%!-- FCC FORM --%>
      <.filter_form form={@form} categories={@categories}/>
    </section>

    <section>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6" id="products-list" phx-update="stream">

        <.product_card :for={{dom_id, product} <- @streams.products} product={product} dom_id={dom_id} />

        </div>
    </section>
    </Layouts.artsy_main>
   """
 end

 @doc """
  Renders the product filtering form. Expect "form" in the assigns.

  """

  attr :form, Phoenix.HTML.Form, required: true
  attr :categories, :list, required: true

 def filter_form(assigns) do
  ~H"""
    <.form for={@form} id="filter-form" phx-change="filter" phx-submit="filter">
        <div class="flex flex-wrap gap-4 items-end">

          <%!-- Search --%>
          <div class="flex-1 min-w-48">
            <.input field={@form[:search]}
              type="text"
              label="Search"
              placeholder="Search products..."
              autocomplete="off"
              phx-debounce="1000"/>
          </div>

          <%!-- Filter by Category --%>
          <div class="min-w-48">
            <.input field={@form[:category_id]} type="select" label="Category" prompt="All categories" options={@categories} />
          </div>

          <%!-- Filter by Artist --%>
          <div class="min-w-48">
            <.input field={@form[:artist]} type="text" label="Artist" prompt="All artists" autocomplete="off" phx-debounce="500"/>
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
            <.link patch={~p"/products"} class="btn btn-ghost">Clear</.link>
          </div>

        </div>
      </.form>
  """
 end




 def handle_event("filter", params, socket) do
  IO.inspect(params, label: "Filter form submitted with params")
    # socket =
    #   socket
    #   |> assign(form: to_form(params))
    #   |> stream(:products, Products.filter_products(params), reset: true)


    params =
      params
      |> Map.take(["search", "category_id", "artist", "sort_by"])
      |> Map.reject(fn {_k, v} -> v in [nil, ""] end)

    socket = push_patch(socket, to: ~p"/products?#{params}")

   {:noreply, socket}
 end

 end
