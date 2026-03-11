defmodule Breeze.Focus do
  @moduledoc false

  @root_scope :__root__

  def build_meta(elements, implicits) do
    Enum.reduce(elements, %{}, fn {_idx, flags}, acc ->
      case Keyword.get(flags, :id) do
        nil ->
          acc

        id ->
          meta =
            flags
            |> Map.new()
            |> Map.merge(extract_implicit_focus_modifiers(flags, Map.get(implicits, id)))
            |> normalize_meta()

          Map.put(acc, id, meta)
      end
    end)
  end

  def remember_focus(focus_memory, nil, _focus_meta), do: focus_memory

  def remember_focus(focus_memory, focused, focus_meta) do
    case Map.get(focus_meta, focused) do
      nil ->
        focus_memory

      meta ->
        scopes = remembered_scopes(meta, focus_meta)
        Enum.reduce(scopes, focus_memory, &Map.put(&2, &1, focused))
    end
  end

  def active_focusables(focusables, focus_meta) do
    case active_trapped_scope_id(focusables, focus_meta) do
      nil -> focusables
      scope_id -> Enum.filter(focusables, &in_scope?(focus_meta, &1, scope_id))
    end
  end

  def normalize_focus(focused, focusables, focus_meta, focus_memory) do
    focusables = active_focusables(focusables, focus_meta)

    cond do
      focusables == [] ->
        nil

      focused in focusables ->
        focused

      true ->
        target_scope = active_trapped_scope_id(focusables, focus_meta)
        pick_focus_target(focusables, target_scope, focus_meta, focus_memory)
    end
  end

  def trapped_scope?(focusables, focus_meta) do
    not is_nil(active_trapped_scope_id(focusables, focus_meta))
  end

  def in_scope?(_focus_meta, nil, _scope_id), do: false

  def in_scope?(focus_meta, id, scope_id) do
    case Map.get(focus_meta, id) do
      %{id: ^scope_id} -> true
      %{scope_path: scope_path} when is_list(scope_path) -> scope_id in scope_path
      _ -> false
    end
  end

  defp pick_focus_target(focusables, scope_id, focus_meta, focus_memory) do
    remembered = Map.get(focus_memory, scope_id || @root_scope)
    default = Enum.find(focusables, &default_focus_target?(focus_meta, &1, scope_id))
    trapped_scope? = match?(%{focus_scope: :trap}, scope_id && Map.get(focus_meta, scope_id))

    cond do
      trapped_scope? and default ->
        default

      remembered in focusables ->
        remembered

      default ->
        default

      true ->
        hd(focusables)
    end
  end

  defp default_focus_target?(focus_meta, id, nil) do
    match?(%{default_focus: true}, Map.get(focus_meta, id))
  end

  defp default_focus_target?(focus_meta, id, scope_id) do
    match?(%{default_focus: true}, Map.get(focus_meta, id)) and
      in_scope?(focus_meta, id, scope_id)
  end

  defp remembered_scopes(meta, focus_meta) do
    scope_path = Map.get(meta, :scope_path, [])

    cond do
      meta.focus_scope == :trap ->
        [meta.id]

      trap_ancestor = List.last(Enum.filter(scope_path, &trapped_scope_id?(focus_meta, &1))) ->
        [trap_ancestor | trailing_scopes_after(scope_path, trap_ancestor)]

      true ->
        [@root_scope | scope_path]
    end
  end

  defp trailing_scopes_after(scope_path, trap_ancestor) do
    scope_path
    |> Enum.drop_while(&(&1 != trap_ancestor))
    |> tl()
  rescue
    _ -> []
  end

  defp trapped_scope_id?(focus_meta, scope_id) do
    match?(%{focus_scope: :trap}, Map.get(focus_meta, scope_id))
  end

  defp active_trapped_scope_id(focusables, focus_meta) do
    focusables
    |> Enum.flat_map(fn id ->
      case Map.get(focus_meta, id) do
        nil ->
          []

        meta ->
          trapped_ancestors = Enum.filter(meta.scope_path, &trapped_scope_id?(focus_meta, &1))

          if meta.focus_scope == :trap do
            trapped_ancestors ++ [id]
          else
            trapped_ancestors
          end
      end
    end)
    |> List.last()
  end

  defp normalize_meta(meta) do
    %{
      id: Map.get(meta, :id),
      implicit_owner: Map.get(meta, :implicit_owner),
      default_focus:
        truthy?(Map.get(meta, :"default-focus")) or truthy?(Map.get(meta, :default_focus)),
      focus_scope:
        normalize_focus_scope(Map.get(meta, :"focus-scope") || Map.get(meta, :focus_scope)),
      scope_path: Map.get(meta, :"focus-scope-path", [])
    }
  end

  defp extract_implicit_focus_modifiers(_flags, nil), do: %{}

  defp extract_implicit_focus_modifiers(flags, {mod, implicit}) do
    mod.handle_modifiers(:root, flags, implicit)
    |> Enum.reduce(%{}, fn
      {:default_focus, value}, acc -> Map.put(acc, :default_focus, value)
      {:focus_scope, value}, acc -> Map.put(acc, :focus_scope, value)
      _, acc -> acc
    end)
  end

  defp normalize_focus_scope(true), do: :contain
  defp normalize_focus_scope("trap"), do: :trap
  defp normalize_focus_scope(:trap), do: :trap
  defp normalize_focus_scope("contain"), do: :contain
  defp normalize_focus_scope(:contain), do: :contain
  defp normalize_focus_scope(_), do: nil

  defp truthy?(value), do: value in [true, "true"]
end
