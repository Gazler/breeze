defmodule TreeExample do
  use Breeze.View
  import Breeze.Blocks

  alias BackBreeze.TextSpan

  def mount(opts, term) do
    root = Keyword.get(opts, :root, File.cwd!()) |> Path.expand()
    # We maintain our own expanded list here because we lazily retrieve the entries
    expanded = [root]
    root_node = directory_node(root, display_root(root), MapSet.new(expanded), root?: true)

    term =
      term
      |> switch_theme(:gruvbox)
      |> focus("repo-tree")
      |> assign(
        root: root,
        nodes: [root_node],
        expanded: expanded,
        selected: root
      )

    {:ok, term}
  end

  def render(assigns) do
    ~H"""
    <box class="w-screen h-screen bg-panel">
      <.tree
        id="repo-tree"
        nodes={@nodes}
        selected={@selected}
        expanded={@expanded}
        virtual
        br-change="select"
        class="w-full h-full"
      >
        <:item :let={row}>{icon_label(row.node.icon, row.node.icon_color, row.label)}</:item>
      </.tree>
    </box>
    """
  end

  def handle_event("select", %{value: value, expanded: expanded}, term) do
    expanded_set = MapSet.new(expanded)

    root_node =
      directory_node(term.assigns.root, display_root(term.assigns.root), expanded_set,
        root?: true
      )

    {:noreply, assign(term, selected: value, expanded: expanded, nodes: [root_node])}
  end

  def handle_event(_, _, term), do: {:noreply, term}
  def handle_info(_, term), do: {:noreply, term}

  defp directory_node(path, label, expanded, opts \\ []) do
    children =
      if MapSet.member?(expanded, path) do
        path
        |> list_entries()
        |> Enum.map(&entry_node(&1, expanded))
      else
        []
      end

    icon = directory_icon(path, expanded, Keyword.get(opts, :root?, false))
    icon_color = {86, 156, 214}

    %{
      id: path,
      label: label,
      icon: icon,
      icon_color: icon_color,
      expandable?: true,
      children: children
    }
  end

  defp entry_node(path, expanded) do
    name = Path.basename(path)

    if File.dir?(path) do
      directory_node(path, name <> "/", expanded)
    else
      {icon, icon_color} = file_icon(name)

      %{
        id: path,
        label: name,
        icon: icon,
        icon_color: icon_color,
        expandable?: false
      }
    end
  end

  defp icon_label(icon, icon_color, label) do
    [
      TextSpan.new(icon <> " ", %{foreground_color: icon_color}),
      TextSpan.new(label)
    ]
  end

  defp list_entries(path) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.map(&Path.join(path, &1))
        |> Enum.sort_by(fn entry ->
          {if(File.dir?(entry), do: 0, else: 1), Path.basename(entry)}
        end)

      {:error, _reason} ->
        []
    end
  end

  defp display_root(path) do
    case System.user_home() do
      nil -> path
      home -> String.replace_prefix(path, home, "~")
    end
  end

  defp directory_icon(path, expanded, _root?),
    do: if(MapSet.member?(expanded, path), do: "", else: "")

  defp file_icon(name) do
    case {String.downcase(name), String.downcase(Path.extname(name))} do
      {"mix.exs", _} -> {"", {154, 103, 174}}
      {"mix.lock", _} -> {"", {154, 103, 174}}
      {"readme.md", _} -> {"", {229, 192, 123}}
      {"licence.md", _} -> {"󰍔", {229, 192, 123}}
      {"license.md", _} -> {"󰍔", {229, 192, 123}}
      {"agents.md", _} -> {"", {229, 192, 123}}
      {_, ".ex"} -> {"", {154, 103, 174}}
      {_, ".exs"} -> {"", {154, 103, 174}}
      {_, ".erl"} -> {"", {196, 67, 98}}
      {_, ".hrl"} -> {"", {196, 67, 98}}
      {_, ".md"} -> {"", {229, 192, 123}}
      {_, ".lock"} -> {"", {224, 108, 117}}
      {_, ".toml"} -> {"", {97, 175, 239}}
      {_, ".json"} -> {"", {229, 192, 123}}
      {_, ".js"} -> {"", {240, 219, 79}}
      {_, ".css"} -> {"", {86, 156, 214}}
      {_, ".html"} -> {"", {227, 79, 38}}
      {_, ".svg"} -> {"󰜡", {255, 181, 46}}
      {_, ".png"} -> {"", {152, 195, 121}}
      {_, ".jpg"} -> {"", {152, 195, 121}}
      {_, ".jpeg"} -> {"", {152, 195, 121}}
      {_, ".gif"} -> {"", {152, 195, 121}}
      {_, ".yml"} -> {"", {97, 175, 239}}
      {_, ".yaml"} -> {"", {97, 175, 239}}
      _ -> {"󰈔", {171, 178, 191}}
    end
  end
end

Breeze.Example.run(
  [
    view: TreeExample,
    theme: Breeze.Theme.builtin(:gruvbox),
    reload: true,
    hide_cursor: true,
    global_keybindings: [
      {"F3", "Theme", &Breeze.View.cycle_theme/2},
      {"q", fn _event, term -> {:stop, term} end}
    ]
  ],
  keep_alive: :infinity
)
