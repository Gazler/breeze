defmodule Breeze.Component do
  @moduledoc """
  Template and component support shared by Breeze views and standalone components.

  Use `Breeze.Component` when a module needs `~H`, attributes, slots, assigns,
  and component definitions without implementing the `Breeze.View` lifecycle.
  """

  @typedoc "Assigns passed to a view or function component."
  @type assigns :: map()

  @typedoc "Compiled template output returned by the `~H` sigil."
  @type rendered :: term()

  defmacro __using__(_opts) do
    quote do
      import Breeze.Component
      Module.register_attribute(__MODULE__, :breeze_components, accumulate: true)
      Module.register_attribute(__MODULE__, :__attrs__, accumulate: true)
      Module.register_attribute(__MODULE__, :__slot_attrs__, accumulate: true)
      Module.register_attribute(__MODULE__, :__slots__, accumulate: true)
      Module.register_attribute(__MODULE__, :__slot__, accumulate: false)
      Module.register_attribute(__MODULE__, :__component_specs__, accumulate: true)
      Module.register_attribute(__MODULE__, :__template_helper_captures__, accumulate: true)
      Module.register_attribute(__MODULE__, :__breeze_template_expressions__, accumulate: true)
      Module.register_attribute(__MODULE__, :__breeze_template_expression_counter__, [])
      Module.put_attribute(__MODULE__, :__breeze_template_expression_counter__, 0)
      Module.register_attribute(__MODULE__, :__breeze_template_patterns__, accumulate: true)
      Module.register_attribute(__MODULE__, :__breeze_template_pattern_counter__, [])
      Module.put_attribute(__MODULE__, :__breeze_template_pattern_counter__, 0)
      @on_definition Breeze.Component
      @before_compile Breeze.Component
    end
  end

  @doc "Compiles a Breeze template from an `~H` sigil."
  defmacro sigil_H({:<<>>, _meta, [source]}, _modifiers) when is_binary(source) do
    unless Macro.Env.has_var?(__CALLER__, {:assigns, nil}) do
      raise "~H requires a variable named \"assigns\" to exist and be set to a map"
    end

    template = Breeze.Template.compile!(source, __CALLER__, module: __CALLER__.module)

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
    template_expressions = pop_template_expressions(env)
    template_patterns = pop_template_patterns(env)
    component_spec_names = Enum.map(component_specs, & &1.name)
    local_components = Enum.uniq(component_spec_names ++ local_component_names(env, components))
    public_components = Enum.filter(local_components, &Module.defines?(env.module, {&1, 1}, :def))

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

    expression_definitions =
      Enum.map(template_expressions, &template_expression_definition/1)

    pattern_definitions =
      Enum.map(template_patterns, &template_pattern_definition/1)

    local_component_definitions =
      Enum.map(local_components, fn component ->
        spec = Enum.find(component_specs, &(&1.name == component))

        quote do
          def __breeze_component__(unquote(component), assigns) do
            assigns =
              Breeze.Component.__apply_component_defaults__(
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
      unquote_splicing(expression_definitions)

      def __breeze_eval_expr__(id, _assigns, _vars) do
        raise ArgumentError, "unknown compiled Breeze template expression: #{inspect(id)}"
      end

      unquote_splicing(pattern_definitions)

      def __breeze_match_pattern__(id, _value, _vars) do
        raise ArgumentError, "unknown compiled Breeze template pattern: #{inspect(id)}"
      end

      unquote_splicing(local_component_definitions)
      unquote_splicing(imported_component_definitions)

      def __breeze_components__, do: unquote(public_components)

      def __breeze_component__(name, _assigns) do
        raise UndefinedFunctionError, module: __MODULE__, function: name, arity: 1
      end
    end
  end

  @doc "Declares an attribute for the next function component."
  defmacro attr(name, type) do
    quote bind_quoted: [name: name, type: type] do
      Breeze.Component.__attr__!(__MODULE__, name, type, [], __ENV__.line, __ENV__.file)
    end
  end

  @doc """
  Declares an attribute for the next function component.

  Options include `:required`, `:default`, and `:doc`.
  """
  defmacro attr(name, type, opts) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      Breeze.Component.__attr__!(__MODULE__, name, type, opts, __ENV__.line, __ENV__.file)
    end
  end

  @doc "Declares a slot for the next function component."
  defmacro slot(name) do
    quote bind_quoted: [name: name] do
      Breeze.Component.__slot__!(__MODULE__, name, [], __ENV__.line, __ENV__.file, fn -> nil end)
    end
  end

  @doc """
  Declares a slot for the next function component.

  Use a `do` block to declare attributes accepted by each slot entry. Options
  include `:required` and `:doc`.
  """
  defmacro slot(name, opts) do
    {block, opts} = Keyword.pop(opts, :do)

    quote do
      Breeze.Component.__slot__!(
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

  defp pop_template_expressions(env) do
    Module.delete_attribute(env.module, :__breeze_template_expression_counter__)

    env.module
    |> Module.delete_attribute(:__breeze_template_expressions__)
    |> List.wrap()
    |> Enum.reverse()
  end

  defp template_expression_definition({id, expr, vars}) do
    assigns_var = Macro.var(:assigns, Breeze.Template)
    vars_var = Macro.var(:vars, Breeze.Template)

    bindings =
      Enum.map(vars, fn name ->
        variable = Macro.var(name, nil)

        quote generated: true do
          unquote(variable) = Map.get(unquote(vars_var), unquote(name))
        end
      end)

    quote generated: true do
      def __breeze_eval_expr__(unquote(id), unquote(assigns_var), unquote(vars_var)) do
        unquote_splicing(bindings)
        unquote(expr)
      end
    end
  end

  defp pop_template_patterns(env) do
    Module.delete_attribute(env.module, :__breeze_template_pattern_counter__)

    env.module
    |> Module.delete_attribute(:__breeze_template_patterns__)
    |> List.wrap()
    |> Enum.reverse()
  end

  defp template_pattern_definition({id, pattern, vars, pinned_vars}) do
    value_var = Macro.var(:value, Breeze.Template)
    vars_var = Macro.var(:_vars, Breeze.Template)

    bindings =
      Enum.map(pinned_vars, fn name ->
        variable = Macro.var(name, nil)

        quote generated: true do
          unquote(variable) = Map.get(unquote(vars_var), unquote(name))
        end
      end)

    result =
      {:%{}, [], Enum.map(vars, fn name -> {name, Macro.var(name, nil)} end)}

    quote generated: true do
      def __breeze_match_pattern__(unquote(id), unquote(value_var), unquote(vars_var)) do
        unquote_splicing(bindings)

        case unquote(value_var) do
          unquote(pattern) -> {:ok, unquote(result)}
          _ -> :error
        end
      end
    end
  end

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
end
