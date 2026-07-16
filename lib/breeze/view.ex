defmodule Breeze.View do
  @moduledoc """
  A Breeze View is a process that handles events, updates its states and renders
  to the terminal. Breeze Views are inspired by Phoenix LiveView, but not 100%
  compatible.

  ## Prior art

  Breeze's template/component ergonomics are inspired by Phoenix LiveView.
  Relevant upstream modules:

  * https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_component.ex
  * https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_live_view/tag_engine.ex

  ## Usage

  The module can be used by including `use Breeze.View`:

  ```elixir
  defmodule Demo do
    use Breeze.View
  end
  ```

  `use Breeze.View` declares the `Breeze.View` behaviour. The callbacks are
  optional because the same module is also used to define component-only
  modules, but a root view must implement `render/1`.

  ## Initial state

  The initial state can be set in the mount callback:

  ```elixir
  def mount(_opts, term), do: {:ok, assign(term, counter: 0)}
  ```

  ## Rendering

  Rendering is performed using Breeze's `~H` template sigil.


  ```elixir
  def render(assigns) do
    ~H"<box>Counter: <%= @counter %></box>"
  end
  ```

  There are a handful of supported attributes:


  * `id` - the id of the element. This is required for focusables and implicits
  * `focusable` - if the element should be added to the focus tree. These are added in
  the order they appear, and can be toggled using tab/shift-tab. The `focus` style
  state can be used to style these. E.g. class="border focus:border-3"
  * `default-focus` - marks the preferred focus target when a view or focus scope becomes active
  * `focus-scope` - defines a focus region. Set `focus-scope="trap"` to keep tab traversal inside it
  * `class` - token-based styling for the box. This is covered in the [Style](`m:Breeze.View#module-style`) section.
  * `style` - inline style maps or `%BackBreeze.Style{}` values for the box. Passing a binary remains backwards compatible.
  * `implicit` - this is a module that will be used for implicit state. This is covered
   in the [Implicits](`m:Breeze.View#module-implicits`) section.

  ## Handling events

  Events that come from the terminal or an implicit are handled in the
  optional `handle_event/3` callback:

  ```elixir
  def handle_event(_, %{"key" => "ArrowUp"}, term) do
    {:noreply, assign(term, counter: term.assigns.counter + 1)}
  end

  def handle_event(_, %{"key" => "ArrowDown"}, term) do
    {:noreply, assign(term, counter: term.assigns.counter - 1)}
  end

  def handle_event(_, %{"key" => "q"}, term) do
    {:stop, term}
  end

  def handle_event(_, _, term) do
    {:noreply, term}
  end
  ```

  For convenience, keys are converted to a more friendly representation for example,
  instead of sending "\eA" which is provided by the terminal, we convert it to "ArrowUp".

  If `handle_event/3` is not implemented, events that reach the view are
  ignored. If it is implemented, normal Elixir function clause matching
  applies.

  Any other messages sent to the process are handled using the optional
  `handle_info/2` callback:

  ```elixir
  def handle_info(:some_message, term), do: {:noreply, term}
  ```

  If `handle_info/2` is not implemented, those messages are ignored.

  ## Style

  Breeze supports two styling inputs:

  * `class` - string tokens such as `border`, `width-15`, `text-3`
  * `style` - a `%BackBreeze.Style{}` struct or a map for inline values

  Passing a binary to `style` remains supported for backwards compatibility.

  A box can be styled similar to CSS using the class attribute:

  ```heex
  <box class="bold text-3 border width-15">Hello World</box>
  ```

  Inline maps can be used when you want direct `BackBreeze` values:

  ```heex
  <box style={%{border: :rounded, border_color: 3, width: 15}}>Hello World</box>
  ```

  The following styles are supported:

   * `border` - add a line border to the box
   * `border-square` - add a square block border to the box
   * `bold` - make the text bold
   * `italic` - make the text italic
   * `inverse` - reverse the foreground-background
   * `reverse` - reverse the foreground-background
   * `block` - display the element as a block
   * `inline` - display the elements inline (join horizontally)
   * `hidden` - collapse the element and hide its contents
   * `grid` - lay out child elements in a grid
   * `grid-cols-n` - set the number of grid columns
   * `grid-rows-n` - set the number of grid rows
   * `gap-x-n` - set the horizontal gap between grid cells
   * `gap-y-n` - set the vertical gap between grid cells
   * `width-x` - set the width of the element
   * `height-x` - set the height of the element
   * `overflow-hidden` - clip child content to the viewport
   * `offset-top-x` - vertically scroll content by x rows
   * `offset-left-x` - horizontally scroll content by x columns
   * `absolute` - position the elements absolute relative to the parent

  ### Grid layout

  Grid children flow from left to right and then onto the next row. Use
  `grid-cols-n` and, when a fixed row count is useful, `grid-rows-n` to define
  the tracks. `gap-x-n` and `gap-y-n` add horizontal and vertical spacing in
  terminal cells.

  ```heex
  <box class="grid grid-cols-2 grid-rows-2 gap-x-1 gap-y-1 width-full">
    <box>One</box>
    <box>Two</box>
    <box>Three</box>
    <box>Four</box>
  </box>
  ```

  ### Responsive styles

  Responsive modifiers apply styles at or above a minimum terminal width.
  Unprefixed styles provide the base layout, and prefixed styles override them
  as the terminal grows:

  | Modifier | Minimum width |
  |----------|---------------|
  | `sm:`    | 40 columns    |
  | `md:`    | 60 columns    |
  | `lg:`    | 80 columns    |
  | `xl:`    | 120 columns   |
  | `2xl:`   | 160 columns   |

  ```heex
  <box class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
    <box>Always shown</box>
    <box class="hidden md:block">Shown from 60 columns</box>
    <box class="hidden lg:block">Shown from 80 columns</box>
  </box>
  ```

  Responsive and state modifiers can be chained. For example,
  `md:focus:border-primary` requires at least 60 columns and focus. Responsive
  styles are reevaluated whenever the terminal is resized. Hidden elements do
  not participate in layout or grid track counting until a display utility such
  as `md:block` reveals them.

  The current dimensions and active breakpoint are available to templates as
  `@breeze.terminal.width`, `@breeze.terminal.height`, and
  `@breeze.breakpoint`.

  ### Colors

   * `text` - set the foreground to the theme's default text color
   * `bg` - set the background to the theme's default background color
   * `text-x` - set the foreground color
   * `bg-x` - set the background color
   * `border-x` - set the border color
   * `scrollbar-x` - set the scrollbar color
   * `placeholder-text-x` - set an input placeholder's foreground color

  For the color classes above, `x` can be a numeric ANSI color index or a
  theme variable such as `primary`, `muted`, or `panel`. See
  [Breeze.Theme](`m:Breeze.Theme`) for the complete variable reference and
  custom theme configuration.

  ```heex
  <box class="bg-panel border-primary text-muted">Status</box>
  ```

  ## Implicits

  Implicits add stateful event handling outside the view. Implement the
  [Breeze.Implicit](`m:Breeze.Implicit`) behaviour to package that logic as a
  reusable renderer extension.

  For example, consider a list component:

  ```heex
  def render(assigns) do
    ~H\"\"\"
    <.list id="my-list" br-change="my_custom_event">
      <:item value="hello">Hello</:item>
      <:item value="world">World</:item>
      <:item value="foo">Foo</:item>
    </.list>
    \"\"\"
  end

  def handle_event("my_custom_event", %{value: value}, term), do: ...
  ```

  Ideally, we don't want to have to keep track of the selected value, handle key
  events, scroll position, viewport overflow, etc. within our view. We might
  only care about the selected value. In this case, we can define the list
  component to use an implicit state module.

  ```heex
  attr :id, :string, required: true
  attr :rest, :global

  slot :item do
    attr :value, :string, required: true
  end

  def list(assigns) do
    ~H\"\"\"
    <box
      id={@id}
      focusable
      class="border focus:border-primary"
      implicit={MyAppList}
      {@rest}
    >
      <box
        :for={item <- @item}
        value={item.value}
        class="selected:bg-primary selected:text-background focus:selected:bg-accent focus:selected:text-background"
      >
        {render_slot(item)}
      </box>
    </box>
    \"\"\"
  end
  ```

  The implicit module is first called with an `init/3` callback. It receives all child
  element attributes, root attributes for the implicit container, and the previous state.

  `init` returns `{:ok, state}` or `{:ok, state, options}`. The options form is used for
  renderer-driven animation behavior such as periodic rerenders.

  ```elixir
  defmodule MyAppList do
    @behaviour Breeze.Implicit

    def init(children, root_attrs, last_state) do
      {:ok,
       %{values: Enum.map(children, &(&1.value)), selected: last_state[:selected], root: root_attrs}}
    end
  end
  ```

  ```elixir
  def init(_children, _root_attrs, last_state) do
    {:ok, last_state, rerender_every: 500}
  end
  ```

  If `rerender_every` is set, Breeze will periodically call `animate/5` when it is
  implemented. The final argument includes timing context such as `:now`,
  `:frame`, `:last_render_at`, `:last_interaction_at`, `:pending?`, and `:focused?`.

  There is also a `handle_event/3` callback. This is similar to the callback for a view, but
  returns different values. Here we handle key events and return a `:change` event along
  with the new state. The `:change` will be used by `br-change` to pass through to the handle_event
  callback of the Breeze.View.

  ```elixir
  def handle_event(_, %{"key" => "ArrowDown"}, %{values: values} = state) do
    index = Enum.find_index(values, &(&1 == state.selected))
    value = if index, do: Enum.at(values, index + 1) || hd(values), else: hd(values)
    {{:change, %{value: value}}, %{state | selected: value}}
  end

  def handle_event(_, %{"key" => "ArrowUp"}, %{values: values} = state) do
    index = Enum.find_index(values, &(&1 == state.selected))
    first = hd(Enum.reverse(values))
    value = if index, do: Enum.at(values, index - 1) || first, else: first
    {{:change, %{value: value}}, %{state | selected: value}}
  end

  def handle_event(_, _, state), do: {:noreply, state}
  ```

  There are two final handlers used during rendering.

  `animate/5` can transform the rendered `BackBreeze.Box` for lightweight
  renderer-driven animation and other presentation changes. It can return either
  the updated box directly or `{:ok, box, overlays: overlays}` to request
  terminal overlays during async animation passes.

  `handle_modifiers/3` receives `:root` or `:child` as the first argument and can be
  used to tell the renderer things about the state.

  Return values can include style flags (for example `selected: true`) and structured
  scroll modifiers (`scroll_y`, `scroll_x`, or `scroll: {top, left}`).

  Root implicit modifiers can also influence focus handling:

  * `default_focus: true` - mark the root element as the preferred focus target
  * `focus_scope: :trap` - constrain tab/shift-tab navigation to this implicit subtree

  ```elixir
  def handle_modifiers(:child, attributes, state) do
    if state.selected == Keyword.get(attributes, :value) do
      [selected: true]
    else
      []
    end
  end

  def handle_modifiers(:root, _attributes, state) do
    [scroll_y: state.offset]
  end
  ```

  """

  @typedoc "Assigns passed to a view or function component."
  @type assigns :: Breeze.Component.assigns()

  @typedoc "A view event name."
  @type event_name :: term()

  @typedoc "A decoded terminal or implicit event payload."
  @type event :: map()

  @typedoc "Compiled template output returned by the `~H` sigil."
  @type rendered :: Breeze.Component.rendered()

  @typedoc "An option returned alongside an event or message reply."
  @type reply_option :: {:invalidate, boolean()}

  @typedoc "A valid return value from a view event or message callback."
  @type reply ::
          {:noreply, Breeze.Term.t()}
          | {:noreply, Breeze.Term.t(), [reply_option()]}
          | {:stop, Breeze.Term.t()}
          | {:stop, Breeze.Term.t(), [reply_option()]}

  @doc "Initializes a view with its startup options and term state."
  @callback mount(keyword(), Breeze.Term.t()) :: {:ok, Breeze.Term.t()}

  @doc "Renders a view or component from its assigns."
  @callback render(assigns()) :: rendered()

  @doc "Handles a terminal or implicit event."
  @callback handle_event(event_name(), event(), Breeze.Term.t()) :: reply()

  @doc "Handles a message sent to the view process."
  @callback handle_info(term(), Breeze.Term.t()) :: reply()

  @optional_callbacks mount: 2, render: 1, handle_event: 3, handle_info: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour Breeze.View
      import Breeze.View, except: [assign: 2, render_slot: 1, render_slot: 2]
      use Breeze.Component
    end
  end

  @doc "Renders a component slot. This delegates to `Breeze.Component.render_slot/1`."
  @spec render_slot(nil | Breeze.Component.slot_entry() | [Breeze.Component.slot_entry()]) ::
          binary()
  defdelegate render_slot(slot), to: Breeze.Component

  @doc "Renders a component slot with assigns. This delegates to `Breeze.Component.render_slot/2`."
  @spec render_slot(
          nil | Breeze.Component.slot_entry() | [Breeze.Component.slot_entry()],
          map() | keyword() | nil
        ) :: binary()
  defdelegate render_slot(slot, assigns), to: Breeze.Component

  @doc "Merges values into term or component assigns via `Breeze.Component.assign/2`."
  @spec assign(map(), Enumerable.t()) :: map()
  defdelegate assign(term_or_assigns, values), to: Breeze.Component

  @doc """
  Append a flash message to `assigns.breeze.flash`.

  The resulting flash assign is a stack-friendly list consumed by
  `Breeze.Blocks.flash_group/1`.

      term
      |> put_flash(:info, "Saved", max: 3, duration: 5_000)
      |> put_flash(:error, "Publish failed", id: "publish-error", highlight: "error")

  The left highlight strip can be customized with `:highlight` or `:color`.
  It accepts Breeze semantic color names, ANSI color indexes, RGB tuples, and
  `"#rgb"`/`"#rrggbb"` hex strings.
  """
  @spec put_flash(map(), atom() | String.t(), term(), keyword() | map()) :: map()
  def put_flash(term_or_assigns, kind, message, opts \\ []) do
    update_flash(term_or_assigns, &Breeze.Flash.put(&1, kind, message, opts))
  end

  @doc """
  Clear flash messages from `assigns.breeze.flash`.

  Without a second argument all flash messages are removed. With a second
  argument, messages matching that kind or id are removed.
  """
  @spec clear_flash(map(), atom() | String.t() | nil) :: map()
  def clear_flash(term_or_assigns, kind_or_id \\ nil) do
    update_flash(term_or_assigns, &Breeze.Flash.clear(&1, kind_or_id))
  end

  @doc false
  def __expire_flash__(term_or_assigns, id, token) do
    update_flash(term_or_assigns, &Breeze.Flash.expire(&1, id, token))
  end

  @doc "Sets the focused element ID, or clears focus when `value` is `nil`."
  @spec focus(Breeze.Term.t(), String.t() | nil) :: Breeze.Term.t()
  def focus(term, value) do
    %{term | focused: value, allow_unfocused?: is_nil(value)}
  end

  @doc """
  Set keybindings that are active anywhere inside the current view subtree.
  """
  def put_local_keybindings(%{local_keybindings: _} = term, bindings) do
    %{term | local_keybindings: Breeze.Keybindings.normalize_list(bindings)}
  end

  @doc """
  Set keybindings that are only active when the given local focus target is focused.
  """
  def put_focus_keybindings(%{focus_keybindings: focus_keybindings} = term, focus_id, bindings)
      when is_binary(focus_id) do
    normalized = Breeze.Keybindings.normalize_list(bindings)
    %{term | focus_keybindings: Map.put(focus_keybindings, focus_id, normalized)}
  end

  @doc """
  Return the currently active keybinding hints for the term.
  """
  def active_keybindings(%{assigns: assigns}) when is_map(assigns) do
    get_in(assigns, [:breeze, :keybindings]) || []
  end

  @doc """
  Set the active Breeze theme for the current term.
  """
  def put_theme(%{theme: _} = term, theme) do
    theme_source =
      case Breeze.Theme.new(theme, terminal: term.terminal) do
        %Breeze.Theme{variables: %{requested_theme: requested_theme}}
        when not is_nil(requested_theme) ->
          requested_theme

        _ ->
          theme
      end

    %{
      term
      | theme: Breeze.Theme.new(theme, terminal: term.terminal),
        theme_source: theme_source,
        apply_theme_defaults?: Breeze.Theme.defaults_enabled?(theme)
    }
  end

  @doc """
  Set a named theme and update `assigns.breeze.theme` metadata.

  The theme can be one of Breeze's built-in cycle names (`:system16`, `:system`,
  `:nebula`, `:catppuccin`, `:dracula`, `:commander`, `:gruvbox`, `:nord`,
  `:solarized_light`, or `:solarized_dark`) or a `{name, theme}` tuple.
  """
  @spec switch_theme(map(), atom() | {term(), term()}, keyword()) :: map()
  def switch_theme(%{theme: _} = term, theme, opts \\ []) when is_list(opts) do
    {name, theme} = resolve_theme(theme)

    term
    |> put_theme(theme)
    |> put_breeze_theme_metadata(name, opts)
  end

  @doc "Cycles a term through Breeze's standard theme set."
  @spec cycle_theme(map()) :: map()
  def cycle_theme(%{theme: _} = term), do: cycle_theme(term, [])

  @doc """
  Cycles a term through a configurable theme set, or handles a global
  keybinding event using the standard theme set.

  Pass `:themes` with a list of built-in names or `{name, theme}` tuples to
  customize the cycle. The event-handler form can be used directly in a global
  keybinding:

      global_keybindings: [{"F3", "Cycle theme", &Breeze.View.cycle_theme/2}]
  """
  @spec cycle_theme(map(), keyword()) :: map()
  @spec cycle_theme(term(), map()) :: {:noreply, map()}
  def cycle_theme(%{theme: _} = term, opts) when is_list(opts) do
    current = current_theme_name(term, opts)

    case Breeze.Theme.next_theme(
           current,
           Keyword.get(opts, :themes, Breeze.Theme.default_cycle())
         ) do
      nil ->
        term

      {name, theme} ->
        term
        |> put_theme(theme)
        |> put_breeze_theme_metadata(name, opts)
    end
  end

  def cycle_theme(_event, %{theme: _} = term), do: {:noreply, cycle_theme(term)}

  @doc "Handles a global keybinding event using a configurable theme set."
  @spec cycle_theme(term(), map(), keyword()) :: {:noreply, map()}
  def cycle_theme(_event, %{theme: _} = term, opts) when is_list(opts),
    do: {:noreply, cycle_theme(term, opts)}

  defp current_theme_name(term, opts) do
    Keyword.get(opts, :current) ||
      get_in(term.assigns, [:breeze, :theme, :name]) ||
      get_in(term.assigns, [Keyword.get(opts, :mode_assign, :theme_mode)]) ||
      theme_source_name(term.theme_source)
  end

  defp theme_source_name(:system16), do: :system16
  defp theme_source_name(:system), do: :system
  defp theme_source_name(_theme_source), do: nil

  defp resolve_theme({name, theme}), do: {name, theme}
  defp resolve_theme(:system16), do: {:system16, :system16}
  defp resolve_theme(:system), do: {:system, :system}
  defp resolve_theme(name) when is_atom(name), do: {name, Breeze.Theme.builtin(name)}

  defp put_breeze_theme_metadata(term, name, opts) do
    if Keyword.get(opts, :assign, true) do
      update_in(term.assigns, fn assigns ->
        breeze =
          assigns
          |> Map.get(:breeze, %{})
          |> then(fn
            value when is_map(value) -> value
            _ -> %{}
          end)
          |> Map.put(:theme, theme_metadata(term, name))

        Map.put(assigns, :breeze, breeze)
      end)
    else
      term
    end
  end

  defp theme_metadata(term, name) do
    %{
      name: name,
      actual_mode: term.theme.mode,
      status: Breeze.Theme.probe_status(term.theme) || :ready
    }
  end

  @doc """
  Reset the implicit state for the given element ID, causing it to reinitialise
  on the next render.
  """
  @spec reset(map(), String.t()) :: map()
  def reset(term, id) do
    update_in(term.implicit_state, &Map.delete(&1, id))
  end

  @doc """
  Update the implicit state for the given element ID in place.
  """
  @spec update_implicit(map(), String.t(), ({module(), map()} -> map())) :: map()
  def update_implicit(term, id, fun) do
    update_in(term.implicit_state, fn implicit_state ->
      case Map.get(implicit_state, id) do
        {mod, state} -> Map.put(implicit_state, id, {mod, fun.({mod, state})})
        nil -> implicit_state
      end
    end)
  end

  @doc """
  Set the implicit state for the given element ID.
  """
  @spec put_implicit(map(), String.t(), module(), map()) :: map()
  def put_implicit(term, id, mod, state) when is_binary(id) and is_atom(mod) do
    update_in(term.implicit_state, &Map.put(&1, id, {mod, state}))
  end

  defp update_flash(%{assigns: assigns} = term, fun) when is_map(assigns) do
    breeze = flash_breeze_assign(assigns)

    flash =
      breeze
      |> Map.get(:flash)
      |> fun.()
      |> schedule_flash_timers(term)

    %{term | assigns: Map.put(assigns, :breeze, Map.put(breeze, :flash, flash))}
  end

  defp update_flash(assigns, fun) when is_map(assigns) do
    breeze = flash_breeze_assign(assigns)
    Map.put(assigns, :breeze, Map.put(breeze, :flash, fun.(Map.get(breeze, :flash))))
  end

  defp flash_breeze_assign(assigns) do
    case Map.get(assigns, :breeze) do
      breeze when is_map(breeze) -> breeze
      _ -> %{}
    end
  end

  defp schedule_flash_timers(flash, %{view: view}) when not is_nil(view) do
    Breeze.Flash.schedule_visible(flash, fn message, duration ->
      Process.send_after(self(), message, duration)
    end)
  end

  defp schedule_flash_timers(flash, _term), do: flash
end
