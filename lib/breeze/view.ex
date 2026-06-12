defmodule Breeze.View do
  @moduledoc """
  A Breeze View is a process that handles events, updates its states and renders
  to the terminal. Breeze Views are inspired by Phoenix LiveView, but not 100%
  compatible.

  > #### Warning {: .warning}
  >
  > This API is unstable and very likely to change.

  ## Prior art

  Breeze's template/component ergonomics are inspired by Phoenix LiveView.
  Relevant upstream modules:

  * https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_component.ex
  * https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_live_view/tag_engine.ex

  ## Usage

  The module can be used by including `use Breeze.View`:

  ```
  defmodule Demo do
    use Breeze.View
  end
  ```

  ## Initial state

  The initial state can be set in the mount callback:

  ```
  def mount(_opts, term), do: {:ok, assign(term, counter: 0)}
  ```

  ## Rendering

  Rendering is performed using Breeze's `~H` template sigil.


  ```
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

  Any events that come from the terminal or an implicit are handled in the `handle_event/3` callback:

  ```
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

  Any other messages sent to the process will be handled using `handle_info/2`:

  ```
  def handle_info(:some_message, term), do: {:noreply, term}
  ```

  ## Style

  Breeze supports two styling inputs:

  * `class` - string tokens such as `border`, `width-15`, `text-3`
  * `style` - a `%BackBreeze.Style{}` struct or a map for inline values

  Passing a binary to `style` remains supported for backwards compatibility.

  A box can be styled similar to CSS using the class attribute:

  ```
  <box class="bold text-3 border width-15">Hello World</box>
  ```

  Inline maps can be used when you want direct `BackBreeze` values:

  ```
  <box style={%{border: :rounded, border_color: 3, width: 15}}>Hello World</box>
  ```

  The following styles are supported:

   * `border` - add a line border to the box
   * `border-square` - add a square block border to the box
   * `bold` - make the text bold
   * `italic` - make the text italic
   * `inverse` - reverse the foreground-background
   * `reverse` - reverse the foreground-background
   * `inline` - display the elements inline (join horizontally)
   * `width-x` - set the width of the element
   * `height-x` - set the height of the element
   * `overflow-hidden` - clip child content to the viewport
   * `offset-top-x` - vertically scroll content by x rows
   * `offset-left-x` - horizontally scroll content by x columns
   * `absolute` - position the elements absolute relative to the parent
   * `border-x` - set the border color where x is a number
   * `bg-x` - set the background color where x is a number
   * `text-x` - set the foreground color where x is a number

  ## Implicits

  Implicits provide a way of adding event handler/state that exists outside of the view
  these should be abstracted out into their own components.

  For example, consider a list component:

  ```
  def render(assigns) do
  ~H\"\"\"
  <.list id={id} br-change="my_custom_event">
  <:item value="hello">Hello</:item>
  <:item value="world">World</:item>
  <:item value="foo">Foo</:item>
  </.list>
  \"\"\"

  def handle_event("my_custom_event", %{value: value}, term), do: ...
  ```

  Ideally, we don't want to have to keep track of the selected value, handle key events,
  etc within our view. In our view, we might only care about the selected value. In this case, we can define the list component to use an implicit state module.

  ```
  attr :id, :string, required: true
  attr :rest, :global

  slot :item do
    attr :value, :string, required: true
  end

  def list(assigns) do
    ~H\"\"\"
    <box focusable class="border focus:border-3" implicit={MyAppList} id={@id} {@rest}>
      <box
        :for={item <- @item}
        value={item.value}
        class="selected:bg-24 selected:text-0 focus:selected:text-7 focus:selected:bg-4"
      ><%= render_slot(item, %{}) %></box>
    </box>
    \"\"\"
  end
    ```

  The implicit module is first called with an `init/2` callback (or optional `init/3`).
  It receives all child element attributes and the previous state. The `init/3` form
  also receives root attributes for the implicit container.

  `init` can either return the implicit state directly, or `{:ok, state, options}`.
  The options form is used for renderer-driven animation behavior such as periodic rerenders.

  ```
  defmodule MyAppList do

    def init(children, root_attrs, last_state) do
      %{values: Enum.map(children, &(&1.value)), selected: last_state[:selected], root: root_attrs}
    end
  end
  ```

  ```
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

  ```
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

  ```
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

  defmacro __using__(_opts) do
    quote do
      import Breeze.View
      Module.register_attribute(__MODULE__, :breeze_components, accumulate: true)
      Module.register_attribute(__MODULE__, :__attrs__, accumulate: true)
      Module.register_attribute(__MODULE__, :__slot_attrs__, accumulate: true)
      Module.register_attribute(__MODULE__, :__slots__, accumulate: true)
      Module.register_attribute(__MODULE__, :__slot__, accumulate: false)
      Module.register_attribute(__MODULE__, :__component_specs__, accumulate: true)
      Module.register_attribute(__MODULE__, :__template_helper_captures__, accumulate: true)
      @on_definition Breeze.View
      @before_compile Breeze.View
    end
  end

  defmacro sigil_H({:<<>>, _meta, [source]}, _modifiers) when is_binary(source) do
    unless Macro.Env.has_var?(__CALLER__, {:assigns, nil}) do
      raise "~H requires a variable named \"assigns\" to exist and be set to a map"
    end

    template = Breeze.Template.compile!(source, __CALLER__)

    template
    |> Breeze.Template.component_names()
    |> Enum.each(&Module.put_attribute(__CALLER__.module, :breeze_components, &1))

    template
    |> Breeze.Template.local_helper_captures()
    |> Enum.each(&Module.put_attribute(__CALLER__.module, :__template_helper_captures__, &1))

    quote do
      _ = var!(assigns)
      {unquote(Macro.escape(template)), var!(assigns)}
    end
  end

  defmacro __before_compile__(env) do
    attrs = pop_attrs(env)
    slots = pop_slots(env)

    validate_misplaced_attrs!(attrs, env.file, fn ->
      "cannot define attributes without a related function component"
    end)

    validate_misplaced_slots!(slots, env.file, fn ->
      "cannot define slots without a related function component"
    end)

    components =
      env.module
      |> Module.get_attribute(:breeze_components)
      |> Enum.uniq()

    component_specs = pop_component_specs(env)
    helper_captures = pop_template_helper_captures(env)
    component_spec_names = Enum.map(component_specs, & &1.name)
    local_components = Enum.uniq(component_spec_names ++ local_component_names(env, components))

    helper_definitions =
      helper_captures
      |> Enum.uniq()
      |> Enum.map(fn {name, arity} ->
        args = Macro.generate_arguments(arity, __MODULE__)

        quote do
          def __breeze_eval_helper__(unquote(name), unquote(arity), [unquote_splicing(args)]) do
            unquote({name, [], args})
          end
        end
      end)

    local_component_definitions =
      Enum.map(local_components, fn component ->
        spec = Enum.find(component_specs, &(&1.name == component))

        quote do
          def __breeze_component__(unquote(component), assigns) do
            assigns =
              Breeze.View.__apply_component_defaults__(
                assigns,
                unquote(Macro.escape((spec && spec.attrs) || [])),
                unquote(Macro.escape((spec && spec.slots) || []))
              )

            unquote(component)(assigns)
          end
        end
      end)

    imported_component_definitions =
      components
      |> Enum.reject(&(&1 in local_components))
      |> Enum.map(fn component ->
        imported_fun = Macro.var(component, nil)

        case imported_component_module(env, component) do
          nil ->
            quote do
              def __breeze_component__(unquote(component), assigns),
                do: unquote(component)(assigns)
            end

          module ->
            quote do
              def __breeze_component__(unquote(component), assigns) do
                _ = &(unquote(imported_fun) / 1)

                if function_exported?(unquote(module), :__breeze_components__, 0) and
                     unquote(component) in unquote(module).__breeze_components__() do
                  unquote(module).__breeze_component__(unquote(component), assigns)
                else
                  apply(unquote(module), unquote(component), [assigns])
                end
              end
            end
        end
      end)

    quote do
      unquote_splicing(helper_definitions)
      unquote_splicing(local_component_definitions)
      unquote_splicing(imported_component_definitions)

      def __breeze_components__, do: unquote(local_components)

      def __breeze_component__(name, _assigns) do
        raise UndefinedFunctionError, module: __MODULE__, function: name, arity: 1
      end
    end
  end

  defmacro attr(name, type) do
    quote bind_quoted: [name: name, type: type] do
      Breeze.View.__attr__!(__MODULE__, name, type, [], __ENV__.line, __ENV__.file)
    end
  end

  defmacro attr(name, type, opts) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      Breeze.View.__attr__!(__MODULE__, name, type, opts, __ENV__.line, __ENV__.file)
    end
  end

  defmacro slot(name) do
    quote bind_quoted: [name: name] do
      Breeze.View.__slot__!(__MODULE__, name, [], __ENV__.line, __ENV__.file, fn -> nil end)
    end
  end

  defmacro slot(name, opts) do
    {block, opts} = Keyword.pop(opts, :do)

    quote do
      Breeze.View.__slot__!(
        __MODULE__,
        unquote(name),
        unquote(opts),
        __ENV__.line,
        __ENV__.file,
        fn -> unquote(block) end
      )
    end
  end

  def __attr__!(module, name, type, opts, line, file) when is_atom(name) and is_list(opts) do
    slot = Module.get_attribute(module, :__slot__)
    {doc, opts} = Keyword.pop(opts, :doc, nil)
    {required, opts} = Keyword.pop(opts, :required, false)

    if not (is_binary(doc) or is_nil(doc) or doc == false) do
      compile_error!(line, file, ":doc must be a string or false, got: #{inspect(doc)}")
    end

    if not is_boolean(required) do
      compile_error!(line, file, ":required must be a boolean, got: #{inspect(required)}")
    end

    key = if slot, do: :__slot_attrs__, else: :__attrs__

    Module.put_attribute(module, key, %{
      slot: slot,
      name: name,
      type: type,
      required: required,
      opts: opts,
      doc: doc,
      line: line
    })

    :ok
  end

  def __slot__!(module, name, opts, line, file, block_fun) when is_atom(name) and is_list(opts) do
    {doc, opts} = Keyword.pop(opts, :doc, nil)
    {required, opts} = Keyword.pop(opts, :required, false)

    if not (is_binary(doc) or is_nil(doc) or doc == false) do
      compile_error!(line, file, ":doc must be a string or false, got: #{inspect(doc)}")
    end

    if not is_boolean(required) do
      compile_error!(line, file, ":required must be a boolean, got: #{inspect(required)}")
    end

    Module.put_attribute(module, :__slot__, name)

    slot_attrs =
      try do
        block_fun.()
        module |> Module.get_attribute(:__slot_attrs__) |> List.wrap() |> Enum.reverse()
      after
        Module.put_attribute(module, :__slot__, nil)
        Module.delete_attribute(module, :__slot_attrs__)
      end

    Module.put_attribute(module, :__slots__, %{
      name: name,
      required: required,
      opts: opts,
      doc: doc,
      line: line,
      attrs: slot_attrs
    })

    :ok
  end

  def __on_definition__(env, kind, name, args, _guards, _body) do
    attrs = pop_attrs(env)
    slots = pop_slots(env)

    if attrs != [] or slots != [] do
      if kind in [:def, :defp] and length(args) == 1 do
        register_component_spec(env, name, slots, attrs)

        if kind == :def do
          register_component_doc(env, slots, attrs)
        end
      else
        validate_misplaced_attrs!(attrs, env.file, fn ->
          case length(args) do
            1 ->
              "could not define attributes for function #{name}/1"

            arity ->
              "cannot declare attributes for function #{name}/#{arity}. Components must be functions with arity 1"
          end
        end)

        validate_misplaced_slots!(slots, env.file, fn ->
          case length(args) do
            1 ->
              "could not define slots for function #{name}/1"

            arity ->
              "cannot declare slots for function #{name}/#{arity}. Components must be functions with arity 1"
          end
        end)
      end
    end
  end

  @doc false
  def __apply_component_defaults__(assigns, attrs, slots) do
    assigns = Map.new(assigns || %{})

    attrs
    |> Enum.reduce(assigns, fn
      %{type: :global, name: name}, acc ->
        Map.put_new(acc, name, [])

      %{name: name, opts: opts}, acc ->
        case Keyword.fetch(opts, :default) do
          {:ok, default} -> Map.put_new(acc, name, default)
          :error -> acc
        end
    end)
    |> then(fn assigns ->
      Enum.reduce(slots, assigns, fn %{name: name}, acc ->
        Map.put_new(acc, name, [])
      end)
    end)
  end

  defp register_component_spec(env, name, slots, attrs) do
    Module.put_attribute(env.module, :__component_specs__, %{
      name: name,
      attrs: attrs,
      slots: slots
    })
  end

  defp register_component_doc(env, slots, attrs) do
    case Module.get_attribute(env.module, :doc) do
      {_line, false} ->
        :ok

      {line, doc} ->
        Module.put_attribute(env.module, :doc, {line, build_component_doc(doc, slots, attrs)})

      nil ->
        Module.put_attribute(env.module, :doc, {env.line, build_component_doc("", slots, attrs)})
    end
  end

  defp build_component_doc(doc, slots, attrs) do
    [left | right] = String.split(doc, "[INSERT LVATTRDOCS]")

    IO.iodata_to_binary([
      build_left_doc(left),
      build_component_docs(slots, attrs),
      build_right_doc(right)
    ])
  end

  defp build_left_doc(""), do: [""]
  defp build_left_doc(left), do: [left, ?\n]

  defp build_right_doc(""), do: []
  defp build_right_doc(right), do: [?\n, right]

  defp build_component_docs([], []), do: []
  defp build_component_docs(slots, []), do: [build_slots_docs(slots)]
  defp build_component_docs([], attrs), do: [build_attrs_docs(attrs)]

  defp build_component_docs(slots, attrs),
    do: [build_attrs_docs(attrs), ?\n, build_slots_docs(slots)]

  defp build_attrs_docs(attrs) do
    [
      "## Attributes\n",
      for attr <- attrs, attr.doc != false and attr.type != :global do
        [
          "\n* ",
          build_attr_name(attr),
          build_attr_type(attr),
          build_attr_required(attr),
          build_hyphen(attr),
          build_attr_doc_and_default(attr, "  ")
        ]
      end,
      case Enum.find(attrs, &(&1.type == :global)) do
        nil -> []
        attr -> build_attr_doc_and_default(attr, "  ")
      end
    ]
  end

  defp build_slots_docs(slots) do
    [
      "## Slots\n",
      for slot <- slots, slot.doc != false do
        slot_attrs = Enum.filter(slot.attrs, &(&1.doc != false and &1.slot == slot.name))

        [
          "\n* ",
          build_slot_name(slot),
          build_slot_required(slot),
          build_slot_doc(slot, slot_attrs)
        ]
      end
    ]
  end

  defp build_slot_name(%{name: name}), do: ["`", Atom.to_string(name), "`"]
  defp build_slot_required(%{required: true}), do: [" (required)"]
  defp build_slot_required(_), do: []

  defp build_slot_doc(%{doc: nil}, []), do: []
  defp build_slot_doc(%{doc: doc}, []), do: [" - ", build_doc(doc, "  ", false)]

  defp build_slot_doc(%{doc: nil}, slot_attrs),
    do: [" - Accepts attributes:\n", build_slot_attrs_docs(slot_attrs)]

  defp build_slot_doc(%{doc: doc}, slot_attrs) do
    [
      " - ",
      build_doc(doc, "  ", true),
      "Accepts attributes:\n",
      build_slot_attrs_docs(slot_attrs)
    ]
  end

  defp build_slot_attrs_docs(slot_attrs) do
    for slot_attr <- slot_attrs do
      [
        "\n  * ",
        build_attr_name(slot_attr),
        build_attr_type(slot_attr),
        build_attr_required(slot_attr),
        build_hyphen(slot_attr),
        build_attr_doc_and_default(slot_attr, "    ")
      ]
    end
  end

  defp build_attr_name(%{name: name}), do: ["`", Atom.to_string(name), "` "]
  defp build_attr_type(%{type: type}), do: ["(`", inspect(type), "`)"]
  defp build_attr_required(%{required: true}), do: [" (required)"]
  defp build_attr_required(_), do: []

  defp build_attr_doc_and_default(%{doc: doc, type: :global, opts: opts}, indent) do
    [
      "\n* Global attributes are accepted.",
      if(doc, do: [" ", build_doc(doc, indent, false)], else: []),
      case Keyword.get(opts, :include) do
        inc when is_list(inc) and inc != [] ->
          [" Supports all globals plus: ", build_literal(inc), "."]

        _ ->
          []
      end
    ]
  end

  defp build_attr_doc_and_default(%{doc: doc, opts: opts}, indent) do
    case Keyword.fetch(opts, :default) do
      {:ok, default} ->
        if doc do
          [build_doc(doc, indent, true), "Defaults to ", build_literal(default), "."]
        else
          ["Defaults to ", build_literal(default), "."]
        end

      :error ->
        if doc, do: [build_doc(doc, indent, false)], else: []
    end
  end

  defp build_doc(doc, indent, text_after?) do
    doc = String.trim(doc)
    [head | tail] = String.split(doc, ["\r\n", "\n"])
    dot = if String.ends_with?(doc, "."), do: [], else: [?.]

    tail =
      Enum.map(tail, fn
        "" -> "\n"
        other -> [?\n, indent | other]
      end)

    case tail do
      [] when text_after? -> [[head | tail], dot, ?\s]
      [] -> [[head | tail], dot]
      _ when text_after? -> [[head | tail], "\n\n", indent]
      _ -> [[head | tail], "\n"]
    end
  end

  defp build_literal(literal), do: [?`, inspect(literal, charlists: :as_list), ?`]
  defp build_hyphen(%{doc: doc}) when is_binary(doc), do: [" - "]
  defp build_hyphen(%{opts: []}), do: []
  defp build_hyphen(%{opts: _}), do: [" - "]

  defp pop_attrs(env),
    do: env.module |> Module.delete_attribute(:__attrs__) |> List.wrap() |> Enum.reverse()

  defp pop_slots(env),
    do: env.module |> Module.delete_attribute(:__slots__) |> List.wrap() |> Enum.reverse()

  defp pop_component_specs(env),
    do:
      env.module
      |> Module.delete_attribute(:__component_specs__)
      |> List.wrap()
      |> Enum.reverse()

  defp pop_template_helper_captures(env),
    do:
      env.module
      |> Module.delete_attribute(:__template_helper_captures__)
      |> List.wrap()
      |> Enum.reverse()

  defp local_component_names(env, components) do
    Enum.filter(components, fn component ->
      Module.defines?(env.module, {component, 1}, :def) or
        Module.defines?(env.module, {component, 1}, :defp)
    end)
  end

  defp imported_component_module(env, component) do
    Enum.find_value(env.functions, fn
      {module, functions} ->
        if module != Kernel and Enum.member?(Keyword.get_values(functions, component), 1) do
          module
        end

      _ ->
        nil
    end)
  end

  defp validate_misplaced_attrs!([], _file, _message_fun), do: :ok

  defp validate_misplaced_attrs!([%{line: line} | _], file, message_fun) do
    compile_error!(line, file, message_fun.())
  end

  defp validate_misplaced_slots!([], _file, _message_fun), do: :ok

  defp validate_misplaced_slots!([%{line: line} | _], file, message_fun) do
    compile_error!(line, file, message_fun.())
  end

  defp compile_error!(line, file, msg) do
    raise CompileError, line: line, file: file, description: msg
  end

  @typedoc "Runtime slot entry generated by Breeze.Template"
  @type slot_entry :: %{optional(atom()) => term(), __breeze_slot__: (map() -> iodata())}

  @doc """
  Render a slot value using empty assigns.

  Accepts `nil`, a single slot entry, or a list of slot entries.
  """
  @spec render_slot(nil | slot_entry() | [slot_entry()]) :: binary()
  def render_slot(slot), do: render_slot(slot, %{})

  @doc """
  Render a slot value with assigns passed to the slot render function.
  """
  @spec render_slot(nil | slot_entry() | [slot_entry()], map() | keyword() | nil) :: binary()
  def render_slot(nil, _), do: ""

  def render_slot(slots, assigns) when is_list(slots) do
    Enum.map_join(slots, "", &render_slot(&1, assigns))
  end

  def render_slot(%{__breeze_slot__: fun}, assigns) when is_function(fun, 1) do
    fun.(Map.new(assigns || %{}))
  end

  def render_slot(_slot, _) do
    ""
  end

  @doc """
  Merge values into `term.assigns`, or into a plain assigns map inside a component function.
  """
  @spec assign(map(), Enumerable.t()) :: map()
  def assign(%{assigns: _} = term, values) do
    %{term | assigns: Map.merge(term.assigns, Map.new(values))}
  end

  def assign(assigns, values) when is_map(assigns) do
    Map.merge(assigns, Map.new(values))
  end

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
  `:nebula`, `:catppuccin`, `:dracula`, `:gruvbox`, `:nord`,
  `:solarized_light`, or `:solarized_dark`) or a `{name, theme}` tuple.
  """
  @spec switch_theme(map(), atom() | {term(), term()}, keyword()) :: map()
  def switch_theme(%{theme: _} = term, theme, opts \\ []) when is_list(opts) do
    {name, theme} = Breeze.Theme.resolve_theme(theme)

    term
    |> put_theme(theme)
    |> put_breeze_theme_metadata(name, opts)
  end

  @doc """
  Cycle through Breeze's standard theme set.

  This can be used directly as a global keybinding handler:

      global_keybindings: [{"F3", "Cycle theme", &Breeze.View.cycle_theme/2}]

  For custom cycles, pass `:themes` with a list of built-in names or
  `{name, theme}` tuples.
  """
  @spec cycle_theme(map(), keyword()) :: map()
  def cycle_theme(%{theme: _} = term), do: cycle_theme(term, [])

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
end
