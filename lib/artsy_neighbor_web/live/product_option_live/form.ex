defmodule ArtsyNeighborWeb.ProductOptionLive.Form do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.ProductOption

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage product_option records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="product_option-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:descr]} type="textarea" label="Descr" />
        <.input
          field={@form[:values]}
          type="select"
          multiple
          label="Values"
          options={[{"Option 1", "option1"}, {"Option 2", "option2"}]}
        />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Product option</.button>
          <.button navigate={return_path(@return_to, @product_option)}>Cancel</.button>
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
    product_option = Products.get_product_option!(id)

    socket
    |> assign(:page_title, "Edit Product option")
    |> assign(:product_option, product_option)
    |> assign(:form, to_form(Products.change_product_option(product_option)))
  end

  defp apply_action(socket, :new, _params) do
    product_option = %ProductOption{}

    socket
    |> assign(:page_title, "New Product option")
    |> assign(:product_option, product_option)
    |> assign(:form, to_form(Products.change_product_option(product_option)))
  end

  @impl true
  def handle_event("validate", %{"product_option" => product_option_params}, socket) do
    changeset = Products.change_product_option(socket.assigns.product_option, product_option_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"product_option" => product_option_params}, socket) do
    save_product_option(socket, socket.assigns.live_action, product_option_params)
  end

  defp save_product_option(socket, :edit, product_option_params) do
    case Products.update_product_option(socket.assigns.product_option, product_option_params) do
      {:ok, product_option} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product option updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, product_option))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_product_option(socket, :new, product_option_params) do
    case Products.create_product_option(product_option_params) do
      {:ok, product_option} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product option created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, product_option))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _product_option), do: ~p"/product_options"
  defp return_path("show", product_option), do: ~p"/product_options/#{product_option}"
end
