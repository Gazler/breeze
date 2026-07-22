defmodule Breeze.Docs.BlockPreviews do
  @moduledoc false

  alias Breeze.Test
  alias Breeze.Theme

  @output_path Path.expand("doc_src/generated/blocks.md", File.cwd!())
  @snapshot_dir Path.expand("doc_src/generated/block_previews", File.cwd!())

  def output_path, do: @output_path
  def snapshot_dir, do: @snapshot_dir

  @themes [
    {:nebula, "Nebula"},
    {:catppuccin, "Catppuccin Mocha"},
    {:dracula, "Dracula"},
    {:commander, "Commander Blue"},
    {:gruvbox, "Gruvbox Dark"},
    {:nord, "Nord"},
    {:solarized_light, "Solarized Light"},
    {:solarized_dark, "Solarized Dark"}
  ]
  @default_theme :gruvbox

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
      {"Button",
       [
         {"Default", preview(__MODULE__.ButtonPreview, size: {24, 3})},
         {"Focused", preview(__MODULE__.ButtonPreview, size: {24, 3}, focused: "preview-button")}
       ]},
      {"Dropdown",
       [
         {"Closed", preview(__MODULE__.DropdownPreview, size: {28, 4})},
         {"Open",
          interactive_preview(__MODULE__.DropdownPreview, [size: {28, 6}], fn session ->
            _ = Test.render!(session)
            Test.input(session, "Enter")
          end)}
       ]},
      {"Flash Group",
       [
         {"Default", preview(__MODULE__.FlashGroupPreview, size: {42, 10})},
         {"Square", preview(__MODULE__.SquareFlashGroupPreview, size: {42, 10})},
         {"Rounded", preview(__MODULE__.RoundedFlashGroupPreview, size: {42, 10})}
       ]},
      {"Input",
       [
         {"Default", preview(__MODULE__.InputPreview, size: {36, 3})},
         {"Focused", preview(__MODULE__.InputPreview, size: {36, 3}, focused: "preview-input")}
       ]},
      {"Keybinding Bar",
       [
         {"Default", preview(__MODULE__.KeybindingBarPreview, size: {50, 3})}
       ]},
      {"List",
       [
         {"Initial", preview(__MODULE__.ListPreview, size: {28, 10})},
         {"Selected",
          preview(__MODULE__.SelectedListPreview, size: {28, 10}, focused: "preview-list")}
       ]},
      {"Markdown",
       [
         {"Default", preview(__MODULE__.MarkdownPreview, size: {40, 8})}
       ]},
      {"Modal",
       [
         {"Confirm", preview(__MODULE__.ModalPreview, size: {36, 12})},
         {"Danger", preview(__MODULE__.DangerModalPreview, size: {36, 12})}
       ]},
      {"Panel",
       [
         {"Unfocused", preview(__MODULE__.PanelPreview, size: {32, 8})},
         {"Focused",
          preview(__MODULE__.AlertPanelPreview,
            size: {32, 8},
            focused: "preview-panel-focus"
          )}
       ]},
      {"Scroll",
       [
         {"Top", preview(__MODULE__.ScrollPreview, size: {26, 8})},
         {"Lower",
          preview(__MODULE__.ScrollPreview,
            size: {26, 8},
            focused: "preview-scroll",
            implicit_state: %{
              "preview-scroll" => {Breeze.Implicit.Scroll, %{offset_y: 3}}
            }
          )}
       ]},
      {"Table",
       [
         {"Initial", preview(__MODULE__.TablePreview, size: {44, 8})},
         {"Selected",
          preview(__MODULE__.SelectedTablePreview, size: {44, 8}, focused: "preview-table")}
       ]},
      {"Tabs",
       [
         {"Default", preview(__MODULE__.TabsPreview, size: {42, 8})},
         {"Underline", preview(__MODULE__.TabsUnderlinePreview, size: {42, 8})}
       ]},
      {"Textarea",
       [
         {"Default", preview(__MODULE__.TextareaPreview, size: {42, 7})},
         {"Focused",
          preview(__MODULE__.TextareaPreview, size: {42, 7}, focused: "preview-textarea")}
       ]},
      {"Tree",
       [
         {"Expanded", preview(__MODULE__.TreePreview, size: {32, 10}, focused: "preview-tree")}
       ]}
    ]
  end

  defp preview(view, opts) do
    fn theme ->
      opts =
        opts
        |> Keyword.put(:theme, theme)
        |> Keyword.put_new(:focused, nil)

      render_view(view, opts)
    end
  end

  defp interactive_preview(view, opts, fun) do
    fn theme -> render_with_session(view, Keyword.put(opts, :theme, theme), fun) end
  end

  defp materialize_sections(sections) do
    Enum.map(sections, fn {title, variants} ->
      materialized_variants =
        Enum.map(variants, fn {label, render_fun} ->
          file_path = snapshot_path(title, label)

          previews =
            Enum.map(@themes, fn {id, theme_label} ->
              theme = Theme.builtin(id)
              %{id: id, label: theme_label, theme: theme, content: render_fun.(theme)}
            end)

          default_preview = Enum.find(previews, &(&1.id == @default_theme))
          File.write!(file_path, default_preview.content)
          {label, previews}
        end)

      {title, materialized_variants}
    end)
  end

  defp markdown_for_sections(sections) do
    body =
      Enum.map_join(sections, "\n\n", fn {title, variants} -> render_section(title, variants) end)

    theme_options =
      Enum.map_join(@themes, "\n", fn {id, label} ->
        selected = if id == @default_theme, do: " selected", else: ""
        ~s(<option value="#{id}"#{selected}>#{label}</option>)
      end)

    """
    # Built-in Components

    Breeze ships with a number of built in components called Breeze Blocks.

    <div class="breeze-theme-picker">
      <label for="breeze-component-theme">Preview theme</label>
      <select id="breeze-component-theme" data-breeze-theme-select>
        #{theme_options}
      </select>
    </div>

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
      Enum.map_join(variants, "\n\n", fn {label, previews} ->
        sources = preview_sources_json(previews)

        """
        ### #{label}

        <div class="breeze-ansi" data-ansi-preview="true">
          <script type="application/json" class="breeze-ansi-sources">#{sources}</script>
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

  defp component_ref("Button"), do: "Breeze.Blocks.button/1"
  defp component_ref("Flash Group"), do: "Breeze.Blocks.flash_group/1"
  defp component_ref("Input"), do: "Breeze.Blocks.input/1"
  defp component_ref("Keybinding Bar"), do: "Breeze.Blocks.keybinding_bar/1"
  defp component_ref("List"), do: "Breeze.Blocks.list/1"
  defp component_ref("Table"), do: "Breeze.Blocks.table/1"
  defp component_ref("Dropdown"), do: "Breeze.Blocks.dropdown/1"
  defp component_ref("Tabs"), do: "Breeze.Blocks.tabs/1"
  defp component_ref("Markdown"), do: "Breeze.Blocks.markdown/1"
  defp component_ref("Scroll"), do: "Breeze.Blocks.scroll/1"
  defp component_ref("Panel"), do: "Breeze.Blocks.panel/1"
  defp component_ref("Modal"), do: "Breeze.Blocks.modal/1"
  defp component_ref("Textarea"), do: "Breeze.Blocks.textarea/1"
  defp component_ref("Tree"), do: "Breeze.Blocks.tree/1"

  defp component_code("Button"), do: render_template_source(__MODULE__.ButtonPreview)
  defp component_code("Flash Group"), do: render_template_source(__MODULE__.FlashGroupPreview)
  defp component_code("Input"), do: render_template_source(__MODULE__.InputPreview)

  defp component_code("Keybinding Bar"),
    do: render_template_source(__MODULE__.KeybindingBarPreview)

  defp component_code("List"), do: render_template_source(__MODULE__.ListPreview)
  defp component_code("Table"), do: render_template_source(__MODULE__.TablePreview)
  defp component_code("Dropdown"), do: render_template_source(__MODULE__.DropdownPreview)
  defp component_code("Tabs"), do: render_template_source(__MODULE__.TabsPreview)
  defp component_code("Markdown"), do: render_template_source(__MODULE__.MarkdownPreview)
  defp component_code("Scroll"), do: render_template_source(__MODULE__.ScrollPreview)
  defp component_code("Panel"), do: render_template_source(__MODULE__.PanelPreview)
  defp component_code("Modal"), do: render_template_source(__MODULE__.ModalPreview)
  defp component_code("Textarea"), do: render_template_source(__MODULE__.TextareaPreview)
  defp component_code("Tree"), do: render_template_source(__MODULE__.TreePreview)

  defp theme_color(theme, name) do
    case Theme.resolve_color(theme, name) do
      {red, green, blue} -> "rgb(#{red}, #{green}, #{blue})"
      "#" <> _rest = color -> color
      color when is_binary(color) -> color
      _color -> "inherit"
    end
  end

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

  def keybindings do
    [
      %{key: "q", label: "Quit"},
      %{key: "F1", label: "Help"},
      %{key: "Enter", label: "Open"}
    ]
  end

  def tree_nodes do
    [
      %{
        id: "lib",
        label: "lib",
        children: [
          %{id: "breeze", label: "breeze"},
          %{id: "blocks", label: "blocks.ex"}
        ]
      },
      %{id: "mix", label: "mix.exs"}
    ]
  end

  def table_rows do
    [
      %{id: "tokyo", rank: "1", city: "Tokyo", country: "Japan", population: "37.2m"},
      %{id: "delhi", rank: "2", city: "Delhi", country: "India", population: "32.0m"},
      %{id: "shanghai", rank: "3", city: "Shanghai", country: "China", population: "28.5m"}
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
    session = Test.start!(view, opts)

    try do
      Test.render!(session, opts)
    after
      Test.stop(session)
    end
  end

  defp render_with_session(view, opts, fun) do
    session = Test.start!(view, opts)

    try do
      _ = fun.(session)
      Test.render!(session, opts)
    after
      Test.stop(session)
    end
  end

  defp preview_sources_json(previews) do
    previews
    |> Enum.map_join(",", fn preview ->
      fields = [
        {"theme", to_string(preview.id)},
        {"background", theme_color(preview.theme, :background)},
        {"foreground", theme_color(preview.theme, :text)},
        {"content", Base.encode64(preview.content)}
      ]

      encoded_fields =
        Enum.map_join(fields, ",", fn {key, value} ->
          json_string(key) <> ":" <> json_string(value)
        end)

      "{" <> encoded_fields <> "}"
    end)
    |> then(&("[" <> &1 <> "]"))
  end

  defp json_string(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")

    "\"" <> escaped <> "\""
  end

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

  defmodule ButtonPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      ~H"""
      <.button id="preview-button">Deploy update</.button>
      """
    end
  end

  defmodule FlashGroupPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns =
        Map.put(assigns, :flash, [
          %{id: "saved", kind: :success, title: "Saved", message: "Deployment completed."},
          %{id: "warning", kind: :warning, message: "One worker is restarting."}
        ])

      ~H"""
      <.flash_group id="preview-flash" flash={@flash} width={34} offset={0}/>
      """
    end
  end

  defmodule RoundedFlashGroupPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns =
        Map.put(assigns, :flash, [
          %{id: "failed", kind: :error, title: "Failed", message: "Could not publish release."}
        ])

      ~H"""
      <.flash_group id="preview-flash-rounded" flash={@flash} variant="rounded" width={34} offset={0}/>
      """
    end
  end

  defmodule SquareFlashGroupPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns =
        Map.put(assigns, :flash, [
          %{id: "queued", kind: :info, title: "Queued", message: "Release is ready to publish."}
        ])

      ~H"""
      <.flash_group id="preview-flash-square" flash={@flash} variant="square" width={34} offset={0}/>
      """
    end
  end

  defmodule InputPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :value, "breeze@example.com")

      ~H"""
      <.input id="preview-input" input-value={@value} class="w-34">{@value}</.input>
      """
    end
  end

  defmodule KeybindingBarPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :keybindings, Breeze.Docs.BlockPreviews.keybindings())

      ~H"""
      <.keybinding_bar keybindings={@keybindings}/>
      """
    end
  end

  defmodule TextareaPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :value, "Release notes\n\nAdd theme-aware component previews.")

      ~H"""
      <.textarea id="preview-textarea" textarea-value={@value} class="w-40 h-6"/>
      """
    end
  end

  defmodule TreePreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :nodes, Breeze.Docs.BlockPreviews.tree_nodes())

      ~H"""
      <.tree id="preview-tree" nodes={@nodes} selected="blocks" expanded={["lib"]} class="w-30 h-9"/>
      """
    end
  end

  defmodule ListPreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :items, Breeze.Docs.BlockPreviews.list_items())

      ~H"""
      <.list id="preview-list" class="w-28 h-10" item_class="w-28">
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
      <.list id="preview-list" class="w-28 h-10" item_class="w-28" list-selected="beta">
        <:item :for={{value, label} <- @items} value={value}>{label}</:item>
      </.list>
      """
    end
  end

  defmodule TablePreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :rows, Breeze.Docs.BlockPreviews.table_rows())

      ~H"""
      <.table id="preview-table" rows={@rows}>
        <:col :let={city} label="#" width={4} align="right">{city.rank}</:col>
        <:col :let={city} label="City" width={12}>{city.city}</:col>
        <:col :let={city} label="Country" width={12}>{city.country}</:col>
        <:col :let={city} label="Pop." width={10} align="right">{city.population}</:col>
      </.table>
      """
    end
  end

  defmodule SelectedTablePreview do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}
    def handle_event(_, _, term), do: {:noreply, term}

    def render(assigns) do
      assigns = Map.put(assigns, :rows, Breeze.Docs.BlockPreviews.table_rows())

      ~H"""
      <.table id="preview-table" rows={@rows} selected="delhi">
        <:col :let={city} label="#" width={4} align="right">{city.rank}</:col>
        <:col :let={city} label="City" width={12}>{city.city}</:col>
        <:col :let={city} label="Country" width={12}>{city.country}</:col>
        <:col :let={city} label="Pop." width={10} align="right">{city.population}</:col>
      </.table>
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
      <.tabs id="preview-tabs" selected="logs" class="w-42 h-8">
        <:tab :for={{value, label, body} <- @tabs} value={value} label={label}>
          <box id={"preview-tabs-panel-#{value}"} class="p-1">{body}</box>
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
      <.tabs id="preview-tabs-underline" selected="logs" variant="underline" class="w-42 h-8">
        <:tab :for={{value, label, body} <- @tabs} value={value} label={label}>
          <box id={"preview-tabs-underline-panel-#{value}"} class="p-1">{body}</box>
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
      <.markdown id="preview-markdown" content={@content} width={36} class="w-40 h-8"/>
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
      <.scroll id="preview-scroll" class="w-26 h-8 border">
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
        <box class="p-1">{@body}</box>
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
        <box id="preview-panel-focus" focusable class="p-1">{@body}</box>
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
        <box class="p-1">{@body}</box>
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
        <box class="p-1">{@body}</box>
      </.modal>
      """
    end
  end
end
