defmodule ArtsyNeighborWeb.ProductImageLive.Form do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.ProductImage

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage product_image records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="product_image-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:path]} type="text" label="Path" />
        <.input field={@form[:position]} type="number" label="Position" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Product image</.button>
          <.button navigate={return_path(@return_to, @product_image)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

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
    product_image = Products.get_product_image!(id)

    socket
    |> assign(:page_title, "Edit Product image")
    |> assign(:product_image, product_image)
    |> assign(:form, to_form(Products.change_product_image(product_image)))
  end

  defp apply_action(socket, :new, _params) do
    product_image = %ProductImage{}

    socket
    |> assign(:page_title, "New Product image")
    |> assign(:product_image, product_image)
    |> assign(:form, to_form(Products.change_product_image(product_image)))
  end

  @impl true
  def handle_event("validate", %{"product_image" => product_image_params}, socket) do
    changeset = Products.change_product_image(socket.assigns.product_image, product_image_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"product_image" => product_image_params}, socket) do
    save_product_image(socket, socket.assigns.live_action, product_image_params)
  end

  defp save_product_image(socket, :edit, product_image_params) do
    case Products.update_product_image(socket.assigns.product_image, product_image_params) do
      {:ok, product_image} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product image updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, product_image))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_product_image(socket, :new, product_image_params) do
    case Products.create_product_image(product_image_params) do
      {:ok, product_image} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product image created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, product_image))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _product_image), do: ~p"/product_images"
  defp return_path("show", product_image), do: ~p"/product_images/#{product_image}"
end
