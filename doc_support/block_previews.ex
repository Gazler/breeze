defmodule Breeze.Docs.BlockPreviews do
  @moduledoc false

  alias Breeze.Test
  alias Breeze.Theme

  @output_path Path.expand("doc_src/generated/blocks.md", File.cwd!())
  @snapshot_dir Path.expand("doc_src/generated/block_previews", File.cwd!())

  def output_path, do: @output_path
  def snapshot_dir, do: @snapshot_dir

  @theme Theme.builtin(:gruvbox)

  def write_markdown!(path \\ @output_path) do
    File.mkdir_p!(Path.dirname(path))
    File.mkdir_p!(@snapshot_dir)

    markdown =
      sections()
      |> materialize_sections()
      |> markdown_for_sections()

    File.write!(path, markdown)
  end

  def generate_markdown do
    sections()
    |> materialize_sections()
    |> markdown_for_sections()
  end

  defp sections do
    [
      {"List",
       [
         {"Initial", fn -> render_view(__MODULE__.ListPreview, size: {28, 10}) end},
         {"Selected",
          fn ->
            render_view(__MODULE__.SelectedListPreview, size: {28, 10}, focused: "preview-list")
          end}
       ]},
      {"Dropdown",
       [
         {"Closed", fn -> render_view(__MODULE__.DropdownPreview, size: {28, 4}) end},
         {"Open",
          fn ->
            render_with_session(__MODULE__.DropdownPreview, [size: {28, 6}], fn session ->
              _ = Test.render!(session)
              Test.input(session, "Enter")
            end)
          end}
       ]},
      {"Panel",
       [
         {"Unfocused", fn -> render_view(__MODULE__.PanelPreview, size: {32, 8}) end},
         {"Focused",
          fn ->
            render_view(__MODULE__.AlertPanelPreview,
              size: {32, 8},
              focused: "preview-panel-focus"
            )
          end}
       ]},
      {"Tabs",
       [
         {"Default", fn -> render_view(__MODULE__.TabsPreview, size: {42, 8}) end},
         {"Underline", fn -> render_view(__MODULE__.TabsUnderlinePreview, size: {42, 8}) end}
       ]},
      {"Markdown",
       [
         {"Default", fn -> render_view(__MODULE__.MarkdownPreview, size: {40, 8}) end},
         {"Scrolled",
          fn ->
            render_view(
              __MODULE__.MarkdownPreview,
              size: {40, 8},
              focused: "preview-markdown",
              implicit_state: %{
                "preview-markdown" => {Breeze.Implicit.Scroll, %{offset_y: 2}}
              }
            )
          end}
       ]},
      {"Scroll",
       [
         {"Top", fn -> render_view(__MODULE__.ScrollPreview, size: {26, 8}) end},
         {"Lower",
          fn ->
            render_view(
              __MODULE__.ScrollPreview,
              size: {26, 8},
              focused: "preview-scroll",
              implicit_state: %{
                "preview-scroll" => {Breeze.Implicit.Scroll, %{offset_y: 3}}
              }
            )
          end}
       ]},
      {"Modal",
       [
         {"Confirm", fn -> render_view(__MODULE__.ModalPreview, size: {36, 12}) end},
         {"Danger", fn -> render_view(__MODULE__.DangerModalPreview, size: {36, 12}) end}
       ]}
    ]
  end

  defp materialize_sections(sections) do
    Enum.map(sections, fn {title, variants} ->
      materialized_variants =
        Enum.map(variants, fn {label, render_fun} ->
          file_path = snapshot_path(title, label)
          content = render_fun.()
          File.write!(file_path, content)
          {label, content}
        end)

      {title, materialized_variants}
    end)
  end

  defp markdown_for_sections(sections) do
    body =
      Enum.map_join(sections, "\n\n", fn {title, variants} -> render_section(title, variants) end)

    """
    # Built-in Components

    Breeze ships with a number of built in components called Breeze Blocks.
    #{body}
    """
  end

  defp snapshot_path(title, label) do
    Path.join(@snapshot_dir, "#{slug(title)}--#{slug(label)}.ansi")
  end

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp render_section(title, variants) do
    component_ref = component_ref(title)
    component_code = component_code(title)

    tabs =
      Enum.map_join(variants, "\n\n", fn {label, content} ->
        """
        ### #{label}

        <div class="breeze-ansi" data-ansi-preview="true">
          <script type="text/plain" class="breeze-ansi-source">#{script_safe(content)}</script>
        </div>
        """
      end)

    """
    ## #{title}

    Component: `#{component_ref}`

    <a href="#" class="breeze-code-toggle" aria-expanded="false">Show code</a>

    ```elixir
    #{component_code}
    ```

    <!-- tabs-open -->
    #{tabs}
    <!-- tabs-close -->
    """
  end

  defp component_ref("List"), do: "Breeze.Blocks.list/1"
  defp component_ref("Dropdown"), do: "Breeze.Blocks.dropdown/1"
  defp component_ref("Tabs"), do: "Breeze.Blocks.tabs/1"
  defp component_ref("Markdown"), do: "Breeze.Blocks.markdown/1"
  defp component_ref("Scroll"), do: "Breeze.Blocks.scroll/1"
  defp component_ref("Panel"), do: "Breeze.Blocks.panel/1"
  defp component_ref("Modal"), do: "Breeze.Blocks.modal/1"

  defp component_code("List"), do: render_template_source(__MODULE__.ListPreview)
  defp component_code("Dropdown"), do: render_template_source(__MODULE__.DropdownPreview)
  defp component_code("Tabs"), do: render_template_source(__MODULE__.TabsPreview)
  defp component_code("Markdown"), do: render_template_source(__MODULE__.MarkdownPreview)
  defp component_code("Scroll"), do: render_template_source(__MODULE__.ScrollPreview)
  defp component_code("Panel"), do: render_template_source(__MODULE__.PanelPreview)
  defp component_code("Modal"), do: render_template_source(__MODULE__.ModalPreview)

  def list_items do
    [
      {"alpha", "Alpha"},
      {"beta", "Beta"},
      {"gamma", "Gamma"},
      {"delta", "Delta"}
    ]
  end

  def dropdown_items do
    [
      {"small", "Small"},
      {"medium", "Medium"},
      {"large", "Large"}
    ]
  end

  def tabs_items do
    [
      {"home", "Home", "Home panel"},
      {"logs", "Logs", "Recent logs"},
      {"help", "Help", "Keyboard shortcuts"}
    ]
  end

  def markdown_content do
    """
    # Preview

    Breeze markdown renders headings, `inline code`, and wrapped text.

    - one
    - two
    """
  end

  def scroll_rows do
    Enum.map(1..7, &"Row #{&1}")
  end

  def panel_title, do: "Status"
  def panel_body, do: "Worker healthy"

  def modal_title(:confirm), do: "Confirm"
  def modal_title(:danger), do: "Delete"
  def modal_body(:confirm), do: "Deploy update?"
  def modal_body(:danger), do: "Remove item?"

  defp render_view(view, opts) do
    start_opts = Keyword.put_new(opts, :theme, @theme)
    session = Test.start!(view, start_opts)

    try do
      Test.render!(session, opts)
    after
      Test.stop(session)
    end
  end

  defp render_with_session(view, opts, fun) do
    start_opts = Keyword.put_new(opts, :theme, @theme)
    session = Test.start!(view, start_opts)

    try do
      _ = fun.(session)
      Test.render!(session, opts)
    after
      Test.stop(session)
    end
  end

  defp script_safe(content), do: String.replace(content, "</script>", "<\\/script>")

  defp render_template_source(module) do
    source =
      module
      |> source_path()
      |> File.read!()

    module_name =
      module
      |> Module.split()
      |> List.last()

    pattern =
      ~r/defmodule #{Regex.escape(module_name)} do.*?def render\(assigns\) do\s+.*?~H"""\n(?<template>.*?)\n\s+"""/ms

    case Regex.run(pattern, source, capture: :all_names) do
      [template] -> template
      _ -> raise "could not extract render template for #{module_name}"
    end
  end

  defp source_path(module) do
    module.module_info(:compile)
    |> Keyword.fetch!(:source)
    |> to_string()
  end

  defmodule ListPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :items, Breeze.Docs.BlockPreviews.list_items())

      ~H"""
      <.list id="preview-list" style="width-28 height-10" item_style="width-28">
        <:item :for={{value, label} <- @items} value={value}>{label}</:item>
      </.list>
      """
    end
  end

  defmodule SelectedListPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :items, Breeze.Docs.BlockPreviews.list_items())

      ~H"""
      <.list id="preview-list" style="width-28 height-10" item_style="width-28" list-selected="beta">
        <:item :for={{value, label} <- @items} value={value}>{label}</:item>
      </.list>
      """
    end
  end

  defmodule DropdownPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, focus(term, "preview-dropdown")}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :items, Breeze.Docs.BlockPreviews.dropdown_items())

      ~H"""
      <.dropdown id="preview-dropdown" selected="medium" width={20}>
        <:item :for={{value, label} <- @items} value={value}>{label}</:item>
      </.dropdown>
      """
    end
  end

  defmodule TabsPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :tabs, Breeze.Docs.BlockPreviews.tabs_items())

      ~H"""
      <.tabs id="preview-tabs" selected="logs" style="width-42 height-8">
        <:tab :for={{value, label, body} <- @tabs} value={value} label={label}>
          <box id={"preview-tabs-panel-#{value}"} style="padding-1">{body}</box>
        </:tab>
      </.tabs>
      """
    end
  end

  defmodule TabsUnderlinePreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :tabs, Breeze.Docs.BlockPreviews.tabs_items())

      ~H"""
      <.tabs id="preview-tabs-underline" selected="logs" variant="underline" style="width-42 height-8">
        <:tab :for={{value, label, body} <- @tabs} value={value} label={label}>
          <box id={"preview-tabs-underline-panel-#{value}"} style="padding-1">{body}</box>
        </:tab>
      </.tabs>
      """
    end
  end

  defmodule MarkdownPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :content, Breeze.Docs.BlockPreviews.markdown_content())

      ~H"""
      <.markdown id="preview-markdown" content={@content} width={36} style="width-40 height-8" />
      """
    end
  end

  defmodule ScrollPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :rows, Breeze.Docs.BlockPreviews.scroll_rows())

      ~H"""
      <.scroll id="preview-scroll" style="width-26 height-8 border">
        <box :for={row <- @rows}>{row}</box>
      </.scroll>
      """
    end
  end

  defmodule PanelPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns =
        Map.merge(assigns, %{
          title: Breeze.Docs.BlockPreviews.panel_title(),
          body: Breeze.Docs.BlockPreviews.panel_body()
        })

      ~H"""
      <.panel width={30} height={7} id="preview-panel">
        <:title>{@title}</:title>
        <box style="padding-1">{@body}</box>
      </.panel>
      """
    end
  end

  defmodule AlertPanelPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns =
        Map.merge(assigns, %{
          title: Breeze.Docs.BlockPreviews.panel_title(),
          body: Breeze.Docs.BlockPreviews.panel_body()
        })

      ~H"""
      <.panel width={30} height={7} id="preview-panel">
        <:title>{@title}</:title>
        <box id="preview-panel-focus" focusable style="padding-1">{@body}</box>
      </.panel>
      """
    end
  end

  defmodule ModalPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns =
        Map.merge(assigns, %{
          title: Breeze.Docs.BlockPreviews.modal_title(:confirm),
          body: Breeze.Docs.BlockPreviews.modal_body(:confirm)
        })

      ~H"""
      <.modal id="preview-modal" width={24} height={6}>
        <:title>{@title}</:title>
        <box style="padding-1">{@body}</box>
      </.modal>
      """
    end
  end

  defmodule DangerModalPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns =
        Map.merge(assigns, %{
          title: Breeze.Docs.BlockPreviews.modal_title(:danger),
          body: Breeze.Docs.BlockPreviews.modal_body(:danger)
        })

      ~H"""
      <.modal id="preview-danger-modal" width={24} height={6}>
        <:title>{@title}</:title>
        <box style="padding-1">{@body}</box>
      </.modal>
      """
    end
  end
end
