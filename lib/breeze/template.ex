defmodule Breeze.Template do
  @moduledoc """
  Internal compiler/runtime backing Breeze's `~H` sigil.

  This module reimplements a Breeze-focused subset of HEEx concepts.
  Relevant Phoenix LiveView prior art:

  * https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_component.ex
  * https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_live_view/tag_engine.ex
  """

  defstruct [:nodes, :env]

  defguardp is_name_char(char)
            when (char >= ?a and char <= ?z) or (char >= ?A and char <= ?Z) or
                   (char >= ?0 and char <= ?9) or char == ?_ or char == ?- or char == ?: or
                   char == ?.

  defguardp is_ws(char) when char == ?\s or char == ?\n or char == ?\t or char == ?\r

  def compile!(source, %Macro.Env{} = env) when is_binary(source) do
    {nodes, rest} = parse_nodes(source, nil, env, [])

    if rest != "" do
      raise "unexpected trailing template content: #{inspect(rest)}"
    end

    %__MODULE__{nodes: nodes, env: Macro.Env.prune_compile_info(env)}
  end

  def render_to_string({%__MODULE__{} = template, comp_assigns}, _assigns) do
    render(template, comp_assigns)
  end

  def render_to_string(%__MODULE__{} = template, assigns) do
    render(template, assigns)
  end

  def render_to_string(data, _assigns) when is_binary(data), do: data
  def render_to_string(data, _assigns) when is_list(data), do: IO.iodata_to_binary(data)
  def render_to_string(nil, _assigns), do: ""
  def render_to_string(other, _assigns), do: to_string(other)

  def component_names(%__MODULE__{nodes: nodes}), do: component_names(nodes)

  def component_names(nodes) when is_list(nodes) do
    nodes
    |> Enum.flat_map(fn
      {:element, "." <> name, _attrs, _directives, children} ->
        [String.to_atom(name) | component_names(children)]

      {:element, _name, _attrs, _directives, children} ->
        component_names(children)

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  def render(%__MODULE__{nodes: nodes, env: env}, assigns) do
    ctx = %{assigns: normalize_assigns(assigns), vars: %{}, env: env}
    render_nodes(nodes, ctx)
  end

  def render_to_tree({%__MODULE__{} = template, comp_assigns}, _assigns) do
    render_to_tree(template, comp_assigns)
  end

  def render_to_tree(%__MODULE__{nodes: nodes, env: env}, assigns) do
    ctx = %{assigns: normalize_assigns(assigns), vars: %{}, env: env}
    nodes_to_tree(nodes, ctx)
  end

  defp nodes_to_tree(nodes, ctx) do
    Enum.flat_map(nodes, &node_to_tree(&1, ctx))
  end

  defp node_to_tree({:text, segments}, ctx) do
    {acc, trailing_text} =
      Enum.reduce(segments, {[], ""}, fn
        {:expr, expr}, {acc, text} ->
          case render_slot_expr(expr, ctx) do
            {:slot, nodes} ->
              acc = if text == "", do: acc, else: acc ++ [text]
              {acc ++ nodes, ""}

            :not_a_slot ->
              {acc, text <> normalize_output(eval_expr(expr, ctx))}
          end

        literal, {acc, text} when is_binary(literal) ->
          {acc, text <> literal}
      end)

    if trailing_text == "", do: acc, else: acc ++ [trailing_text]
  end

  defp node_to_tree({:expr, expr}, ctx) do
    case render_slot_expr(expr, ctx) do
      {:slot, nodes} ->
        nodes

      :not_a_slot ->
        case eval_expr(expr, ctx) do
          nil -> []
          "" -> []
          other -> [normalize_output(other)]
        end
    end
  end

  defp node_to_tree({:element, name, attrs, directives, children}, ctx) do
    expand_for(directives[:for], ctx)
    |> Enum.flat_map(fn iteration_ctx ->
      if render_if?(directives[:if], iteration_ctx) do
        element_to_tree(name, attrs, children, iteration_ctx)
      else
        []
      end
    end)
  end

  defp render_slot_expr({:render_slot, _meta, [slot_arg]}, ctx) do
    {:slot, expand_slot(eval_expr(slot_arg, ctx), %{}, ctx)}
  end

  defp render_slot_expr({:render_slot, _meta, [slot_arg, assigns_arg]}, ctx) do
    {:slot, expand_slot(eval_expr(slot_arg, ctx), eval_expr(assigns_arg, ctx), ctx)}
  end

  defp render_slot_expr(_expr, _ctx), do: :not_a_slot

  defp expand_slot(nil, _slot_assigns, _ctx), do: []

  defp expand_slot(slots, slot_assigns, _ctx) when is_list(slots) do
    slot_assigns = normalize_assigns(slot_assigns)

    Enum.flat_map(slots, fn
      %{__breeze_slot_raw__: {children, slot_ctx}} ->
        nodes_to_tree(children, %{slot_ctx | vars: Map.merge(slot_ctx.vars, slot_assigns)})

      _ ->
        []
    end)
  end

  defp expand_slot(%{__breeze_slot_raw__: {children, slot_ctx}}, slot_assigns, _ctx) do
    slot_assigns = normalize_assigns(slot_assigns)
    nodes_to_tree(children, %{slot_ctx | vars: Map.merge(slot_ctx.vars, slot_assigns)})
  end

  defp expand_slot(_slot, _slot_assigns, _ctx), do: []

  defp element_to_tree("." <> component, attrs, children, ctx) do
    module = ctx.env.module
    fun = String.to_atom(component)

    attrs = eval_component_attrs(attrs, ctx)
    rest = Enum.filter(attrs, fn {key, _value} -> global_attr?(key) end)

    assigns =
      attrs
      |> Map.new()
      |> maybe_put_rest(rest)
      |> Map.merge(build_slots(children, ctx))

    {%__MODULE__{nodes: comp_nodes, env: comp_env}, comp_assigns} =
      unwrap_component(invoke_component(module, fun, assigns), assigns)

    comp_ctx = %{assigns: comp_assigns, vars: %{}, env: comp_env}
    nodes_to_tree(comp_nodes, comp_ctx)
  end

  defp element_to_tree("live", attrs, _children, ctx) do
    [{:live, Map.new(eval_component_attrs(attrs, ctx))}]
  end

  defp element_to_tree(":" <> _slot_name, _attrs, _children, _ctx), do: []

  defp element_to_tree(name, attrs, children, ctx) do
    attr_nodes =
      attrs
      |> eval_html_attrs(ctx)
      |> Enum.map(fn
        {attr_name, true} -> {:attribute_bool, [attr_name]}
        {attr_name, value} -> {:attribute, [attr_name, to_string(value)]}
      end)

    child_nodes = nodes_to_tree(children, ctx) |> merge_text_nodes()

    [{String.to_atom(name), [], attr_nodes ++ child_nodes}]
  end

  defp merge_text_nodes(nodes) do
    nodes
    |> Enum.reduce([], fn
      text, [prev | rest] when is_binary(text) and is_binary(prev) -> [prev <> text | rest]
      node, acc -> [node | acc]
    end)
    |> Enum.reverse()
  end

  defp render_nodes(nodes, ctx) do
    Enum.map_join(nodes, "", &render_node(&1, ctx))
  end

  defp render_node({:text, segments}, ctx) do
    Enum.map_join(segments, "", fn
      {:expr, expr} -> expr |> eval_expr(ctx) |> normalize_output()
      text when is_binary(text) -> text
    end)
  end

  defp render_node({:expr, expr}, ctx) do
    expr
    |> eval_expr(ctx)
    |> normalize_output()
  end

  defp render_node({:element, name, attrs, directives, children}, ctx) do
    expand_for(directives[:for], ctx)
    |> Enum.map_join("", fn iteration_ctx ->
      if render_if?(directives[:if], iteration_ctx) do
        render_element(name, attrs, children, iteration_ctx)
      else
        ""
      end
    end)
  end

  defp render_element("." <> component, attrs, children, ctx) do
    module = ctx.env.module
    fun = String.to_atom(component)

    attrs = eval_component_attrs(attrs, ctx)

    rest = Enum.filter(attrs, fn {key, _value} -> global_attr?(key) end)

    assigns =
      attrs
      |> Map.new()
      |> maybe_put_rest(rest)
      |> Map.merge(build_slots(children, ctx))

    {template, comp_assigns} =
      unwrap_component(invoke_component(module, fun, assigns), assigns)

    render_to_string(template, comp_assigns)
  end

  defp render_element("live", _attrs, _children, _ctx), do: ""

  defp render_element(":" <> _slot_name, _attrs, _children, _ctx), do: ""

  defp render_element(name, attrs, children, ctx) do
    attrs = eval_html_attrs(attrs, ctx)

    opening = ["<", name, serialize_attrs(attrs), ">"]
    content = render_nodes(children, ctx)
    closing = ["</", name, ">"]

    IO.iodata_to_binary([opening, content, closing])
  end

  defp invoke_component(module, component, assigns) do
    if function_exported?(module, :__breeze_component__, 2) do
      module.__breeze_component__(component, assigns)
    else
      apply(module, component, [assigns])
    end
  end

  defp unwrap_component({%__MODULE__{} = template, comp_assigns}, _caller_assigns) do
    {template, comp_assigns}
  end

  defp unwrap_component(%__MODULE__{} = template, caller_assigns) do
    {template, caller_assigns}
  end

  defp build_slots(children, ctx) do
    {slots, inner_block_nodes} =
      Enum.reduce(children, {%{}, []}, fn
        {:element, ":" <> slot_name, slot_attrs, directives, slot_children}, {slots, inner} ->
          entries =
            expand_for(directives[:for], ctx)
            |> Enum.flat_map(fn slot_ctx ->
              if render_if?(directives[:if], slot_ctx) do
                [slot_entry(slot_attrs, slot_children, slot_ctx)]
              else
                []
              end
            end)

          key = String.to_atom(slot_name)
          {Map.update(slots, key, entries, &(&1 ++ entries)), inner}

        node, {slots, inner} ->
          {slots, inner ++ [node]}
      end)

    if inner_block_nodes == [] do
      slots
    else
      inner_block = [slot_entry([], inner_block_nodes, ctx)]
      Map.put(slots, :inner_block, inner_block)
    end
  end

  defp slot_entry(attrs, children, ctx) do
    slot_attrs = eval_component_attrs(attrs, ctx) |> Map.new()

    render_fun = fn args ->
      args = normalize_assigns(args)
      slot_ctx = %{ctx | vars: Map.merge(ctx.vars, args)}
      render_nodes(children, slot_ctx)
    end

    slot_attrs
    |> Map.put(:__breeze_slot__, render_fun)
    |> Map.put(:__breeze_slot_raw__, {children, ctx})
  end

  defp eval_html_attrs(attrs, ctx) do
    Enum.flat_map(attrs, fn
      {:boolean, name} ->
        [{name, true}]

      {:static, name, value} ->
        [{name, value}]

      {:dynamic, name, expr} ->
        case eval_expr(expr, ctx) do
          nil -> []
          false -> []
          true -> [{name, true}]
          value -> [{name, value}]
        end

      {:spread, expr} ->
        expr
        |> eval_expr(ctx)
        |> spread_pairs(:string)
    end)
  end

  defp eval_component_attrs(attrs, ctx) do
    Enum.flat_map(attrs, fn
      {:boolean, name} ->
        [{String.to_atom(name), true}]

      {:static, name, value} ->
        [{String.to_atom(name), value}]

      {:dynamic, name, expr} ->
        case eval_expr(expr, ctx) do
          nil -> []
          false -> []
          true -> [{String.to_atom(name), true}]
          value -> [{String.to_atom(name), value}]
        end

      {:spread, expr} ->
        expr
        |> eval_expr(ctx)
        |> spread_pairs(:atom)
    end)
  end

  defp maybe_put_rest(assigns, []), do: assigns
  defp maybe_put_rest(assigns, rest), do: Map.put(assigns, :rest, rest)

  defp spread_pairs(value, mode)

  defp spread_pairs(value, mode) when is_map(value) do
    value
    |> Enum.map(fn {key, val} -> {convert_key(key, mode), val} end)
    |> Enum.reject(fn {_key, val} -> val in [nil, false] end)
  end

  defp spread_pairs(value, mode) when is_list(value) do
    if Keyword.keyword?(value) do
      value
      |> Enum.map(fn {key, val} -> {convert_key(key, mode), val} end)
      |> Enum.reject(fn {_key, val} -> val in [nil, false] end)
    else
      []
    end
  end

  defp spread_pairs(_value, _mode), do: []

  defp convert_key(key, :string) when is_atom(key), do: Atom.to_string(key)
  defp convert_key(key, :string) when is_binary(key), do: key
  defp convert_key(key, :string), do: to_string(key)

  defp convert_key(key, :atom) when is_atom(key), do: key
  defp convert_key(key, :atom) when is_binary(key), do: String.to_atom(key)
  defp convert_key(key, :atom), do: key |> to_string() |> String.to_atom()

  defp serialize_attrs(attrs) do
    Enum.map_join(attrs, "", fn
      {name, true} -> " #{name}"
      {name, value} -> " #{name}=\"#{escape_attr(normalize_output(value))}\""
    end)
  end

  defp escape_attr(value) do
    value
    |> String.replace("\"", "&quot;")
  end

  defp global_attr?(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.contains?("-")
  end

  defp global_attr?(key) when is_binary(key) do
    String.contains?(key, "-")
  end

  defp global_attr?(key) do
    key
    |> to_string()
    |> String.contains?("-")
  end

  defp render_if?(nil, _ctx), do: true
  defp render_if?(expr, ctx), do: eval_expr(expr, ctx) not in [false, nil]

  defp expand_for(nil, ctx), do: [ctx]

  defp expand_for({_pattern_string, pattern_expr, enumerable_expr}, ctx) do
    enumerable = eval_expr(enumerable_expr, ctx)

    if is_nil(enumerable) do
      []
    else
      Enum.flat_map(enumerable, fn value ->
        case bind_for_pattern(pattern_expr, value, ctx) do
          {:ok, vars} -> [%{ctx | vars: vars}]
          :error -> []
        end
      end)
    end
  end

  defp bind_for_pattern(pattern_expr, value, ctx) do
    binding = Map.to_list(ctx.vars) ++ [assigns: ctx.assigns, breeze_value: value]

    case Code.eval_quoted(pattern_expr, binding, ctx.env) do
      {{:ok, new_vars}, _} ->
        {:ok, Map.merge(ctx.vars, new_vars)}

      {:error, _} ->
        :error
    end
  end

  defp eval_expr(expr, ctx) do
    binding = Map.to_list(ctx.vars) ++ [assigns: ctx.assigns]
    {value, _binding} = Code.eval_quoted(expr, binding, ctx.env)
    value
  end

  defp normalize_output(nil), do: ""
  defp normalize_output(data) when is_binary(data), do: data
  defp normalize_output(data) when is_list(data), do: IO.iodata_to_binary(data)
  defp normalize_output(data), do: to_string(data)

  defp normalize_assigns(assigns) when is_map(assigns), do: assigns
  defp normalize_assigns(assigns) when is_list(assigns), do: Map.new(assigns)
  defp normalize_assigns(_assigns), do: %{}

  defp parse_nodes("", nil, _env, acc), do: {Enum.reverse(acc), ""}

  defp parse_nodes("", closing, _env, _acc) do
    raise "missing closing tag </#{closing}>"
  end

  defp parse_nodes(source, closing, env, acc) do
    cond do
      String.starts_with?(source, "<%=") ->
        {expr, rest} = take_between(source, "<%=", "%>")
        node = {:expr, compile_expr(expr, env)}
        parse_nodes(rest, closing, env, [node | acc])

      String.starts_with?(source, "</") ->
        {tag_name, rest} = parse_closing_tag(source)

        cond do
          is_nil(closing) ->
            raise "unexpected closing tag </#{tag_name}>"

          tag_name == closing ->
            {Enum.reverse(acc), rest}

          true ->
            raise "expected closing tag </#{closing}> but found </#{tag_name}>"
        end

      String.starts_with?(source, "<") ->
        {name, attrs, directives, self_closing?, rest} = parse_opening_tag(source, env)

        if self_closing? do
          node = {:element, name, attrs, directives, []}
          parse_nodes(rest, closing, env, [node | acc])
        else
          {children, rest} = parse_nodes(rest, name, env, [])
          node = {:element, name, attrs, directives, children}
          parse_nodes(rest, closing, env, [node | acc])
        end

      true ->
        {text, rest} = take_text(source)

        case compile_text_node(text, env) do
          nil -> parse_nodes(rest, closing, env, acc)
          node -> parse_nodes(rest, closing, env, [node | acc])
        end
    end
  end

  defp parse_opening_tag("<" <> rest, env) do
    {name, rest} = take_name(rest)

    if name == "" do
      raise "expected tag name"
    end

    {attrs, directives, self_closing?, rest} =
      parse_attributes(rest, env, [], %{for: nil, if: nil})

    {name, attrs, directives, self_closing?, rest}
  end

  defp parse_closing_tag("</" <> rest) do
    {name, rest} = take_name(rest)
    rest = trim_ws(rest)

    case rest do
      ">" <> rest ->
        {name, rest}

      _ ->
        raise "malformed closing tag </#{name}>"
    end
  end

  defp parse_attributes(source, env, attrs, directives) do
    source = trim_ws(source)

    cond do
      source == "" ->
        raise "malformed opening tag"

      String.starts_with?(source, "/>") ->
        rest = binary_part(source, 2, byte_size(source) - 2)
        {Enum.reverse(attrs), directives, true, rest}

      String.starts_with?(source, ">") ->
        rest = binary_part(source, 1, byte_size(source) - 1)
        {Enum.reverse(attrs), directives, false, rest}

      true ->
        {attr, rest} = parse_attribute(source, env)

        case attr do
          {:directive, :if, expr} ->
            parse_attributes(rest, env, attrs, %{directives | if: expr})

          {:directive, :for, expr} ->
            parse_attributes(rest, env, attrs, %{directives | for: expr})

          _ ->
            parse_attributes(rest, env, [attr | attrs], directives)
        end
    end
  end

  defp parse_attribute("{" <> _rest = source, env) do
    {expr, rest} = take_braced(source)
    {{:spread, compile_expr(expr, env)}, rest}
  end

  defp parse_attribute(source, env) do
    {name, rest} = take_name(source)

    if name == "" do
      raise "expected attribute name"
    end

    rest_trimmed = trim_ws(rest)

    case rest_trimmed do
      "=" <> rest ->
        rest = trim_ws(rest)

        case rest do
          "\"" <> _ ->
            {value, rest} = parse_quoted(rest)
            {build_attribute(name, {:static, value}, env), rest}

          "{" <> _ ->
            {value, rest} = take_braced(rest)
            {build_attribute(name, {:dynamic, value}, env), rest}

          _ ->
            {value, rest} = take_name(rest)
            {build_attribute(name, {:static, value}, env), rest}
        end

      _ ->
        {{:boolean, name}, rest}
    end
  end

  defp build_attribute(":if", {:dynamic, expr}, env) do
    {:directive, :if, compile_expr(expr, env)}
  end

  defp build_attribute(":for", {:dynamic, expr}, env) do
    {pattern, enumerable} = split_for_expression(expr)

    {:directive, :for,
     {pattern, compile_for_pattern(pattern, env), compile_expr(enumerable, env)}}
  end

  defp build_attribute(":if", _other, _env) do
    raise "the :if directive requires an expression, e.g. :if={...}"
  end

  defp build_attribute(":for", _other, _env) do
    raise "the :for directive requires an expression, e.g. :for={x <- ...}"
  end

  defp build_attribute(name, {:dynamic, expr}, env) do
    {:dynamic, name, compile_expr(expr, env)}
  end

  defp build_attribute(name, {:static, value}, _env) do
    {:static, name, value}
  end

  defp compile_text_node(text, env) do
    text = normalize_text(text)

    if text == "" do
      nil
    else
      {:text, compile_text_segments(text, env, [])}
    end
  end

  defp compile_text_segments("", _env, acc), do: Enum.reverse(acc)

  defp compile_text_segments(text, env, acc) do
    case :binary.match(text, "{") do
      :nomatch ->
        acc = if text == "", do: acc, else: [text | acc]
        Enum.reverse(acc)

      {index, 1} ->
        plain = binary_part(text, 0, index)
        rest = binary_part(text, index, byte_size(text) - index)
        {expr, rest} = take_braced(rest)

        acc =
          acc
          |> maybe_push_text(plain)
          |> then(&[{:expr, compile_expr(expr, env)} | &1])

        compile_text_segments(rest, env, acc)
    end
  end

  defp maybe_push_text(acc, ""), do: acc
  defp maybe_push_text(acc, text), do: [text | acc]

  defp normalize_text(text) do
    leading_newline? = Regex.match?(~r/^\s*\n/, text)
    trailing_newline? = Regex.match?(~r/\n\s*$/, text)

    text = String.replace(text, ~r/\n[ \t]*/, " ")
    text = if leading_newline?, do: String.trim_leading(text), else: text
    text = if trailing_newline?, do: String.trim_trailing(text), else: text

    if String.trim(text) == "" do
      ""
    else
      text
    end
  end

  defp split_for_expression(expr) do
    case String.split(expr, "<-", parts: 2) do
      [pattern, enumerable] ->
        pattern = String.trim(pattern)
        enumerable = String.trim(enumerable)

        if pattern == "" or enumerable == "" do
          raise "invalid :for expression: #{inspect(expr)}"
        end

        {pattern, enumerable}

      _ ->
        raise "invalid :for expression: #{inspect(expr)}"
    end
  end

  defp compile_for_pattern(pattern_string, env) do
    pattern_ast = Code.string_to_quoted!(pattern_string, file: env.file, line: env.line)
    vars = collect_pattern_vars(pattern_ast)
    result_map = {:%{}, [], Enum.map(vars, fn name -> {name, {name, [], nil}} end)}

    {:case, [],
     [
       {:breeze_value, [], nil},
       [
         do: [
           {:->, [], [[pattern_ast], {:ok, result_map}]},
           {:->, [], [[{:_, [], nil}], :error]}
         ]
       ]
     ]}
  end

  defp collect_pattern_vars(ast), do: do_collect_vars(ast, []) |> Enum.uniq()

  defp do_collect_vars({:^, _, _}, acc), do: acc
  defp do_collect_vars({:_, _, _}, acc), do: acc

  defp do_collect_vars({name, _meta, ctx}, acc) when is_atom(name) and is_atom(ctx) do
    [name | acc]
  end

  defp do_collect_vars({_form, _meta, args}, acc) when is_list(args) do
    do_collect_vars(args, acc)
  end

  defp do_collect_vars({left, right}, acc) do
    acc |> then(&do_collect_vars(left, &1)) |> then(&do_collect_vars(right, &1))
  end

  defp do_collect_vars(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &do_collect_vars/2)
  end

  defp do_collect_vars(_ast, acc), do: acc

  defp compile_expr(expr, env) do
    expr = String.trim(expr)

    expr
    |> Code.string_to_quoted!(file: env.file, line: env.line)
    |> normalize_assign_refs()
  end

  defp normalize_assign_refs(ast) do
    Macro.prewalk(ast, fn
      {:@, _meta, [{name, _meta2, _ctx}]} when is_atom(name) ->
        {
          {:., [], [{:__aliases__, [alias: false], [:Map]}, :get]},
          [],
          [Macro.var(:assigns, nil), name]
        }

      node ->
        node
    end)
  end

  defp take_between(source, prefix, suffix) do
    rest = binary_part(source, byte_size(prefix), byte_size(source) - byte_size(prefix))

    case :binary.match(rest, suffix) do
      :nomatch ->
        raise "unterminated expression"

      {index, _len} ->
        expr = binary_part(rest, 0, index)

        rest =
          binary_part(
            rest,
            index + byte_size(suffix),
            byte_size(rest) - index - byte_size(suffix)
          )

        {expr, rest}
    end
  end

  defp parse_quoted("\"" <> rest), do: do_parse_quoted(rest, [], false)

  defp do_parse_quoted("", _acc, _escape?) do
    raise "unterminated quoted attribute"
  end

  defp do_parse_quoted("\"" <> rest, acc, false) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp do_parse_quoted("\\" <> rest, acc, false) do
    do_parse_quoted(rest, ["\\" | acc], true)
  end

  defp do_parse_quoted(<<char::utf8, rest::binary>>, acc, true) do
    do_parse_quoted(rest, [<<char::utf8>> | acc], false)
  end

  defp do_parse_quoted(<<char::utf8, rest::binary>>, acc, false) do
    do_parse_quoted(rest, [<<char::utf8>> | acc], false)
  end

  defp take_braced("{" <> rest), do: do_take_braced(rest, 1, [], nil, false)

  defp do_take_braced("", _depth, _acc, _quote, _escape) do
    raise "unterminated {...} expression"
  end

  defp do_take_braced(<<char::utf8, rest::binary>>, depth, acc, quote, true) do
    do_take_braced(rest, depth, [<<char::utf8>> | acc], quote, false)
  end

  defp do_take_braced(<<char::utf8, rest::binary>>, depth, acc, quote, false)
       when quote in [?", ?'] and char == ?\\ do
    do_take_braced(rest, depth, [<<char::utf8>> | acc], quote, true)
  end

  defp do_take_braced(<<char::utf8, rest::binary>>, depth, acc, quote, false)
       when quote in [?", ?'] and char == quote do
    do_take_braced(rest, depth, [<<char::utf8>> | acc], nil, false)
  end

  defp do_take_braced(<<char::utf8, rest::binary>>, depth, acc, quote, false)
       when quote in [?", ?'] do
    do_take_braced(rest, depth, [<<char::utf8>> | acc], quote, false)
  end

  defp do_take_braced(<<char::utf8, rest::binary>>, depth, acc, _quote, false)
       when char in [?", ?'] do
    do_take_braced(rest, depth, [<<char::utf8>> | acc], char, false)
  end

  defp do_take_braced("{" <> rest, depth, acc, nil, false) do
    do_take_braced(rest, depth + 1, ["{" | acc], nil, false)
  end

  defp do_take_braced("}" <> rest, 1, acc, nil, false) do
    expr = acc |> Enum.reverse() |> IO.iodata_to_binary()
    {expr, rest}
  end

  defp do_take_braced("}" <> rest, depth, acc, nil, false) when depth > 1 do
    do_take_braced(rest, depth - 1, ["}" | acc], nil, false)
  end

  defp do_take_braced(<<char::utf8, rest::binary>>, depth, acc, quote, false) do
    do_take_braced(rest, depth, [<<char::utf8>> | acc], quote, false)
  end

  defp take_text(source) do
    case :binary.match(source, "<") do
      :nomatch ->
        {source, ""}

      {index, _len} ->
        text = binary_part(source, 0, index)
        rest = binary_part(source, index, byte_size(source) - index)
        {text, rest}
    end
  end

  defp take_name(source), do: do_take_name(source, [])

  defp do_take_name(<<char::utf8, rest::binary>>, acc) when is_name_char(char) do
    do_take_name(rest, [<<char::utf8>> | acc])
  end

  defp do_take_name(rest, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp trim_ws(<<char::utf8, rest::binary>>) when is_ws(char), do: trim_ws(rest)
  defp trim_ws(source), do: source
end
