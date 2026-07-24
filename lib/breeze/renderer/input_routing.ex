defmodule Breeze.Renderer.InputRouting do
  @moduledoc false

  @routing_structure_attr_names [
    "id",
    "focusable",
    "implicit",
    "disabled",
    "default-focus",
    "focus-scope",
    "br-change",
    "br-submit"
  ]

  def signature(nodes) when is_list(nodes) do
    signature(nodes, false)
  end

  def structure_changed?(previous, desired, focused) do
    focused_structure(previous, focused) != focused_structure(desired, focused) or
      global_structure(previous) != global_structure(desired)
  end

  def focused_implicit_changed?(_signature, nil, _implicit, _meta, _element), do: false
  def focused_implicit_changed?(_signature, _id, nil, _meta, _element), do: false

  def focused_implicit_changed?(signature, id, {mod, state}, meta, element) do
    case find_implicit(signature, id) do
      {:implicit, ^id, _tag, attrs, nested} ->
        desired_mod = attr_value(attrs, "implicit")

        if desired_mod == mod do
          last_state = if is_nil(element), do: state, else: Map.put(state, :__element__, element)
          root_attrs = implicit_root_attrs(attrs, id)
          items = implicit_item_attrs(nested)

          {next_state, next_meta} =
            Breeze.RenderState.init_implicit(mod, items, root_attrs, last_state)

          next_state != state or next_meta != meta
        else
          true
        end

      _entry ->
        true
    end
  end

  def focused_structure(_signature, nil), do: []

  def focused_structure(signature, focused) do
    signature
    |> select_focus_path(focused)
    |> project_structure(:focused)
  end

  def global_structure(signature) do
    project_structure(signature, :global)
  end

  def live_entries(signature) do
    collect_live_entries(signature, %{})
  end

  def contains_focus?(id, focused) when is_binary(id) and is_binary(focused) do
    focused == id or String.starts_with?(focused, id <> "::")
  end

  def contains_focus?(_id, _focused), do: false

  defp signature(nodes, within_implicit?) do
    Enum.flat_map(nodes, &node_signature(&1, within_implicit?))
  end

  defp node_signature({:live, attrs}, _within_implicit?) do
    attrs = normalize_attr_map(attrs)
    [{:live, attr_value(attrs, "id"), attrs}]
  end

  defp node_signature({tag, _metadata, children}, within_implicit?)
       when is_atom(tag) and is_list(children) do
    all_attrs = routing_attrs(children, :all)
    implicit? = attr_truthy?(all_attrs, "implicit")

    attrs =
      if within_implicit? or implicit?,
        do: all_attrs,
        else: routing_attrs(children, :root)

    nested = nested_nodes(children)
    id = attr_value(attrs, "id")
    nested_signature = signature(nested, within_implicit? or implicit?)

    type = if implicit?, do: :implicit, else: :node
    [{type, id, tag, attrs, nested_signature}]
  end

  defp node_signature(_node, _within_implicit?), do: []

  defp routing_attrs(nodes, mode) do
    nodes
    |> Enum.flat_map(fn
      {:attribute, [name, value]} -> [{normalize_attr_name(name), value}]
      {:attribute_bool, [name]} -> [{normalize_attr_name(name), true}]
      _node -> []
    end)
    |> Enum.filter(fn {name, _value} -> routing_attr_name?(name, mode) end)
  end

  defp routing_attr_name?(_name, :all), do: true

  defp routing_attr_name?(name, :root) do
    name in @routing_structure_attr_names or String.starts_with?(name, "capture")
  end

  defp nested_nodes(nodes) do
    Enum.filter(nodes, fn
      {:live, _attrs} -> true
      {tag, _metadata, children} when is_atom(tag) and is_list(children) -> true
      _node -> false
    end)
  end

  defp attr_truthy?(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {^name, value} -> value not in [false, nil]
      nil -> false
    end
  end

  defp attr_value(attrs, name) when is_list(attrs) do
    case List.keyfind(attrs, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp attr_value(attrs, name) when is_map(attrs) do
    Enum.find_value(attrs, fn {attr_name, value} ->
      if normalize_attr_name(attr_name) == name, do: value
    end)
  end

  defp attr_value(_attrs, _name), do: nil

  defp select_focus_path(signature, focused) when is_list(signature) do
    Enum.flat_map(signature, &select_focus_entry(&1, focused))
  end

  defp select_focus_path(_signature, _focused), do: []

  defp select_focus_entry(entry, focused) do
    cond do
      contains_focus?(entry_id(entry), focused) ->
        [focus_target_entry(entry)]

      true ->
        case select_focus_path(entry_children(entry), focused) do
          [] ->
            []

          selected ->
            if entry_type(entry) == :implicit,
              do: [entry],
              else: [put_entry_children(entry, selected)]
        end
    end
  end

  defp project_structure(signature, mode) when is_list(signature) do
    Enum.flat_map(signature, &project_entry(&1, mode))
  end

  defp project_structure(_signature, _mode), do: []

  defp project_entry({:implicit, id, tag, attrs, nested}, mode) do
    attrs = routing_structure_attrs(attrs)
    nested = project_structure(nested, mode)
    [{:implicit, id, tag, attrs, nested}]
  end

  defp project_entry({:live, id, attrs}, :focused) do
    [{:live, id, normalize_and_sort_attrs(attrs)}]
  end

  defp project_entry({:live, id, _attrs}, :global) do
    [{:live, id}]
  end

  defp project_entry({:node, id, tag, attrs, nested}, mode) do
    attrs = routing_structure_attrs(attrs)
    nested = project_structure(nested, mode)

    if meaningful_routing_attrs?(attrs) or nested != [],
      do: [{:node, id, tag, attrs, nested}],
      else: []
  end

  defp routing_structure_attrs(attrs) do
    attrs
    |> normalize_attrs()
    |> Enum.filter(fn {name, _value} -> routing_attr_name?(name, :root) end)
    |> Enum.sort()
  end

  defp meaningful_routing_attrs?(attrs) do
    Enum.any?(attrs, fn {name, _value} -> name != "id" end)
  end

  defp collect_live_entries(signature, acc) when is_list(signature) do
    Enum.reduce(signature, acc, fn
      {:live, id, attrs}, acc ->
        Map.put(acc, id, attrs)

      entry, acc ->
        collect_live_entries(entry_children(entry), acc)
    end)
  end

  defp collect_live_entries(_signature, acc), do: acc

  defp find_implicit(signature, id) when is_list(signature) do
    Enum.find_value(signature, fn
      {:implicit, ^id, _tag, _attrs, _nested} = entry ->
        entry

      entry ->
        find_implicit(entry_children(entry), id)
    end)
  end

  defp find_implicit(_signature, _id), do: nil

  defp implicit_root_attrs(attrs, id) do
    attrs
    |> attrs_to_map()
    |> Map.drop([:focusable, :implicit, :id, :implicit_owner])
    |> Map.put(:id, id)
  end

  defp implicit_item_attrs(signature) when is_list(signature) do
    Enum.flat_map(signature, fn
      {:implicit, _id, _tag, attrs, _nested} ->
        [implicit_attrs(attrs)]

      {:live, _id, _attrs} ->
        []

      {:node, _id, _tag, attrs, nested} ->
        [implicit_attrs(attrs) | implicit_item_attrs(nested)]
    end)
  end

  defp implicit_item_attrs(_signature), do: []

  defp implicit_attrs(attrs) do
    attrs
    |> attrs_to_map()
    |> Map.drop([:focusable, :implicit, :id, :implicit_owner])
  end

  defp attrs_to_map(attrs) do
    Enum.reduce(normalize_attrs(attrs), %{}, fn {name, value}, acc ->
      Map.put(acc, existing_attr_key(name), value)
    end)
  end

  defp existing_attr_key(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> name
  end

  defp entry_type({type, _id, _tag, _attrs, _nested}), do: type
  defp entry_type({:live, _id, _attrs}), do: :live
  defp entry_type(_entry), do: nil

  defp entry_id({:live, id, _attrs}), do: id
  defp entry_id({_type, id, _tag, _attrs, _nested}), do: id
  defp entry_id(_entry), do: nil

  defp entry_children({_type, _id, _tag, _attrs, nested}), do: nested
  defp entry_children(_entry), do: []

  defp focus_target_entry({:node, _id, _tag, _attrs, _nested} = entry) do
    put_entry_children(entry, [])
  end

  defp focus_target_entry(entry), do: entry

  defp put_entry_children({type, id, tag, attrs, _nested}, nested) do
    {type, id, tag, attrs, nested}
  end

  defp normalize_and_sort_attrs(attrs) do
    attrs
    |> normalize_attrs()
    |> Enum.sort()
  end

  defp normalize_attr_map(attrs) do
    attrs
    |> normalize_attrs()
    |> Map.new()
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    Enum.map(attrs, fn {name, value} -> {normalize_attr_name(name), value} end)
  end

  defp normalize_attrs(attrs) when is_list(attrs) do
    Enum.map(attrs, fn
      {name, value} -> {normalize_attr_name(name), value}
      value -> value
    end)
  end

  defp normalize_attrs(_attrs), do: []

  defp normalize_attr_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_attr_name(name), do: to_string(name)
end
