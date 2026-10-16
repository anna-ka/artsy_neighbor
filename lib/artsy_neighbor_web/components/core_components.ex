defmodule ArtsyNeighborWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: ArtsyNeighborWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders a message ("flash").

  Four kinds, each with its own colour and icon (colour is never the only
  clue): `:success`, `:info`, `:warning`, `:error`. Phoenix itself only
  has `:info` and `:error`; the other two are ours, used the same way
  (`put_flash(socket, :success, "...")`).

  The look (success and information tinted, warnings and errors solid,
  decided in Phase D of `docs/plans/2026-10-15-theme-and-components.md`)
  lives in
  `assets/css/app.css` (`msg`, `msg-success`, ...). A message never fades
  by itself: it stays until "Close" is pressed or the page changes.
  Messages are placed (and stacked) by `Layouts.flash_group/1`.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:success} title="Saved.">Your changes are on your page now.</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil, doc: "a few bold words before the message"

  attr :kind, :atom,
    values: [:success, :info, :warning, :error],
    doc: "used for styling and flash lookup"

  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    icons = %{
      success: "hero-check-circle",
      info: "hero-information-circle",
      warning: "hero-exclamation-triangle",
      error: "hero-exclamation-circle"
    }

    assigns =
      assigns
      |> assign_new(:id, fn -> "flash-#{assigns.kind}" end)
      |> assign(:icon_name, Map.fetch!(icons, assigns.kind))

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      role="alert"
      class={["msg pointer-events-auto", "msg-#{@kind}"]}
      {@rest}
    >
      <.icon name={@icon_name} class="msg-icon" />
      <div class="msg-text">
        <span :if={@title} class="msg-title">{@title}</span>
        {msg}
      </div>
      <button
        type="button"
        class="msg-close"
        phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      >
        {gettext("Close")}
      </button>
    </div>
    """
  end

  @doc """
  Renders a button, or a link that looks like one when given `href`,
  `navigate` or `patch`.

  Five kinds (`variant`), chosen in Phase 0 of
  `docs/plans/2026-10-15-theme-and-components.md`:

    * `"main"` - the one most important action in an area ("Save changes")
    * `"ordinary"` (the default) - any other action ("Cancel", "Send message")
    * `"quiet"` - a low-key action that looks like a link ("Clear filters")
    * `"danger"` - an action that removes something ("Delete this work")
    * `"danger_final"` - only the final "Yes, delete" in a confirmation

  While LiveView waits for the server after a click or a form submit, the
  button shows a small turning circle; `phx-disable-with` changes its words
  ("Saving…"). The look lives in `assets/css/app.css` (`btn-base`, ...).
  `class` adds classes (for example `w-full`) on top of the kind's own.

  ## Examples

      <.button>Cancel</.button>
      <.button variant="main" phx-disable-with="Saving…">Save changes</.button>
      <.button variant="quiet" navigate={~p"/"}>Back to the home page</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any, default: nil, doc: "extra classes, added to the kind's own"
  attr :variant, :string, default: "ordinary", values: ~w(main ordinary quiet danger danger_final)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "main" => "btn-main",
      "ordinary" => "btn-ordinary",
      "quiet" => "btn-quiet",
      "danger" => "btn-danger",
      "danger_final" => "btn-danger-final"
    }

    assigns =
      assign(assigns, :class, ["btn-base", Map.fetch!(variants, assigns.variant), assigns.class])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a form field: its label, optional help text, the box itself,
  and any error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  The look was chosen in Phase 0 of
  `docs/plans/2026-10-15-theme-and-components.md` and lives in
  `assets/css/app.css` (`field`, `field-input`, ...):

    * the label is always above the box;
    * `help` text sits between the label and the box, so it is read
      before typing;
    * `optional` adds "(optional)" after the label, in words (instead of
      marking required fields with *);
    * a mistake gives the box a red edge and a sentence under it.

  `class` adds classes to the box, on top of its own.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" label="Email" />
  <.input field={@form[:homepage]} label="Website" optional
          help="Your own site, if you have one." />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :help, :string, default: nil, doc: "a sentence shown between the label and the box"
  attr :optional, :boolean, default: false, doc: "adds \"(optional)\" after the label"
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "extra classes for the box, added to its own"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, fn error -> translate_error(error) end))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class={["field", @errors != [] && "field-has-error"]}>
      <label class="field-check">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class}
          {@rest}
        />
        <span>
          {@label}<.optional_mark :if={@optional} />
          <span :if={@help} class="field-help block">{@help}</span>
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class={["field", @errors != [] && "field-has-error"]}>
      <label>
        <.field_label label={@label} optional={@optional} help={@help} />
        <select
          id={@id}
          name={@name}
          class={["field-input", @class]}
          multiple={@multiple}
          aria-invalid={@errors != [] && "true"}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class={["field", @errors != [] && "field-has-error"]}>
      <label>
        <.field_label label={@label} optional={@optional} help={@help} />
        <textarea
          id={@id}
          name={@name}
          class={["field-input", @class]}
          aria-invalid={@errors != [] && "true"}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class={["field", @errors != [] && "field-has-error"]}>
      <label>
        <.field_label label={@label} optional={@optional} help={@help} />
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={["field-input", @class]}
          aria-invalid={@errors != [] && "true"}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # The words above a box: the label, "(optional)" if asked for, and the
  # help text. Shared by the text, select and textarea fields.
  attr :label, :any, required: true
  attr :optional, :boolean, required: true
  attr :help, :string, required: true

  defp field_label(assigns) do
    ~H"""
    <span :if={@label} class="field-label">{@label}<.optional_mark :if={@optional} /></span>
    <span :if={@help} class="field-help block">{@help}</span>
    """
  end

  defp optional_mark(assigns) do
    ~H"""
    <span class="field-optional"> (optional)</span>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="field-error">
      <.icon name="hero-exclamation-circle" class="size-[18px] shrink-0 mt-px" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(ArtsyNeighborWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ArtsyNeighborWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
