defmodule ArtsyNeighborWeb.AdminProductLive.Form do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Categories

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    product = Products.get_product!(id)

    socket
    |> assign(:page_title, "Edit Product")
    |> assign(:product, product)
    |> assign(:form, to_form(Products.change_product(product)))
    |> assign_selects()
  end

  defp apply_action(socket, :new, _params) do
    product = %Product{}

    socket
    |> assign(:page_title, "New Product")
    |> assign(:product, product)
    |> assign(:form, to_form(Products.change_product(product)))
    |> assign_selects()
  end

  defp assign_selects(socket) do
    artists = Artists.list_artists() |> Enum.map(fn a -> {a.nickname, a.id} end)
    categories = Categories.list_categories() |> Enum.map(fn c -> {c.name, c.id} end)

    socket
    |> assign(:artists, artists)
    |> assign(:categories, categories)
  end

  @impl true
  def handle_event("validate", %{"product" => product_params}, socket) do
    changeset = Products.change_product(socket.assigns.product, product_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"product" => product_params}, socket) do
    save_product(socket, socket.assigns.live_action, product_params)
  end

  defp save_product(socket, :edit, product_params) do
    case Products.update_product(socket.assigns.product, product_params) do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product updated successfully.")
         |> push_navigate(to: return_path(socket.assigns.return_to, product))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_product(socket, :new, product_params) do
    case Products.create_product(product_params) do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product created successfully.")
         |> push_navigate(to: return_path(socket.assigns.return_to, product))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _product), do: ~p"/admin/products"
  defp return_path("show", product), do: ~p"/admin/products/#{product}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>
      <div class="w-full px-8 py-8">

        <.header>
          <%= @page_title %>
        </.header>

        <.form for={@form} id="product-form" phx-change="validate" phx-submit="save">

          <%!-- Title --%>
          <.input
            field={@form[:title]}
            type="text"
            label={raw("Title <span class=\"text-error\">*</span>")}
            placeholder="Product title"
            phx-debounce="blur"
          />

          <%!-- Description --%>
          <.input
            field={@form[:descr]}
            type="textarea"
            label={raw("Description <span class=\"text-error\">*</span>")}
            rows="3"
            phx-debounce="blur"
          />

          <%!-- Details --%>
          <.input
            field={@form[:details]}
            type="textarea"
            label={raw("Details <span class=\"text-error\">*</span>")}
            rows="4"
            phx-debounce="blur"
          />

          <%!-- Price --%>
          <.input
            field={@form[:price]}
            type="number"
            label={raw("Price <span class=\"text-error\">*</span>")}
            step="any"
            phx-debounce="blur"
          />

          <%!-- Artist --%>
          <.input
            field={@form[:artist_id]}
            type="select"
            label={raw("Artist <span class=\"text-error\">*</span>")}
            prompt="Select an artist"
            options={@artists}
          />

          <%!-- Category --%>
          <.input
            field={@form[:category_id]}
            type="select"
            label={raw("Category <span class=\"text-error\">*</span>")}
            prompt="Select a category"
            options={@categories}
          />

          <%!-- Dimensions --%>
          <div class="grid grid-cols-3 gap-4">
            <.input
              field={@form[:width]}
              type="number"
              label="Width"
              step="any"
              phx-debounce="blur"
            />
            <.input
              field={@form[:length]}
              type="number"
              label="Length"
              step="any"
              phx-debounce="blur"
            />
            <.input
              field={@form[:height]}
              type="number"
              label="Height"
              step="any"
              phx-debounce="blur"
            />
          </div>

          <%!-- Units --%>
          <.input
            field={@form[:units]}
            type="select"
            label="Units"
            options={[{"Centimetres (cm)", "cm"}, {"Inches (in)", "in"}]}
          />

          <%!-- Materials --%>
          <.input
            field={@form[:materials]}
            type="text"
            label="Materials"
            placeholder="e.g., Oil on canvas, stretched linen"
            phx-debounce="blur"
          />

          <.button_artsy variant="primary" disable_with="Saving...">
            Save Product
          </.button_artsy>

        </.form>

        <.back navigate={return_path(@return_to, @product)}>
          Back
        </.back>

      </div>
    </Layouts.artsy_main>
    """
  end
end
