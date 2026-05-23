defmodule Breeze.RemoteInspector.View do
  @moduledoc false

  use Breeze.View
  import Breeze.Blocks
  alias BackBreeze.TextSpan

  @render_tree_limit 600

  def global_keybindings do
    [
      {"q", "Quit", &__MODULE__.quit/2},
      {"F4", "Inspector"}
    ]
  end

  def quit(_event, term), do: {:stop, term}

  def mount(_opts, term) do
    {:ok, _pid} = Breeze.RemoteInspector.ensure_server()
    :ok = Breeze.RemoteInspector.subscribe(self())
    state = Breeze.RemoteInspector.snapshot()

    {:ok,
     assign(term,
       snapshots: state.snapshots,
       latest_source: state.latest_source,
       active_source: state.latest_source,
       panel_tab: "overview",
       render_tree_kind: "rendered",
       render_tree_expanded: %{},
       render_trees: %{},
       screen: term.terminal.size
     )
     |> put_tree_keybindings()
     |> refresh_active_render_tree()}
  end

  def render(assigns) do
    active = active_entry(assigns)
    active_source = active_source(assigns)
    render_tree_kind = render_tree_kind(assigns)
    panel_tab = Map.get(assigns, :panel_tab, "overview")
    breeze = assigns |> Map.get(:breeze, %{}) |> Map.put_new(:keybindings, [])
    now = System.system_time(:millisecond)
    active_render_tree = active_render_tree(assigns, active_source, active, render_tree_kind)

    assigns =
      Map.merge(assigns, %{
        active: active,
        active_source: active_source,
        now: now,
        screen_text: format_screen(assigns.screen),
        latest_source_text: format_source(assigns.latest_source),
        source_entries: source_entries(assigns.snapshots, active_source),
        active_source_text: if(active, do: format_source(active.source), else: "-"),
        active_server_text: if(active, do: format_server(active.snapshot), else: "-"),
        active_theme_text: if(active, do: format_theme(active.snapshot.theme), else: "-"),
        active_theme_rows: if(active, do: theme_rows(active.snapshot.theme), else: []),
        active_status_text: if(active, do: status_line(active, now), else: "-"),
        active_counts_text: if(active, do: counts_line(active.snapshot), else: "-"),
        active_selected_text:
          if(active, do: label(active.snapshot.selected, active.snapshot.selected_id), else: "-"),
        active_hovered_text:
          if(active, do: label(active.snapshot.hovered, active.snapshot.hovered_id), else: "-"),
        active_focused_text: if(active, do: active.snapshot.focused || "-", else: "-"),
        active_focusables_text: if(active, do: focusables_summary(active.snapshot), else: "-"),
        active_layout_text: if(active, do: layout_line(active.snapshot.selected), else: "-"),
        active_box_text: if(active, do: box_line(active.snapshot.selected), else: "-"),
        active_layout_data: if(active, do: layout_data(active.snapshot.selected), else: nil),
        active_component_text:
          if(active, do: component_line(active.snapshot.selected), else: "-"),
        active_component_module_text:
          if(active, do: component_module_line(active.snapshot.selected), else: "-"),
        active_component_function_text:
          if(active, do: component_function_line(active.snapshot.selected), else: "-"),
        active_class_text: if(active, do: class_line(active.snapshot.selected), else: "-"),
        active_style_input_text:
          if(active, do: style_input_line(active.snapshot.selected), else: "-"),
        active_color_text: if(active, do: color_line(active.snapshot.selected), else: "-"),
        show_fg_swatch?: show_color_swatch?(active, :foreground_color),
        show_bg_swatch?: show_color_swatch?(active, :background_color),
        fg_swatch_style: swatch_style(active, :foreground_color),
        bg_swatch_style: swatch_style(active, :background_color),
        active_focus_text: if(active, do: focus_line(active.snapshot), else: "-"),
        active_selected_focus_text:
          if(active, do: selected_focus_line(active.snapshot.selected), else: "-"),
        active_flag_rows: if(active, do: flag_rows(active.snapshot.selected), else: []),
        active_implicit_text: if(active, do: implicit_line(active.snapshot.selected), else: "-"),
        active_implicit_detail_text:
          if(active, do: implicit_detail_line(active.snapshot.selected), else: "-"),
        active_fragment_text: if(active, do: fragment_line(active.snapshot.selected), else: "-"),
        active_fragment_render:
          if(active, do: fragment_render_line(active.snapshot.selected, assigns.screen), else: ""),
        active_render_tree: active_render_tree,
        active_render_tree_nodes: if(active, do: render_tree_nodes(active_render_tree), else: []),
        active_render_tree_selected:
          if(active, do: render_tree_selected(active_render_tree, active.snapshot), else: nil),
        active_render_tree_expanded:
          if(active, do: render_tree_expanded(active_render_tree), else: []),
        render_tree_kind: render_tree_kind,
        breeze: breeze,
        panel_tab: panel_tab
      })

    ~H"""
    <box class="width-screen height-screen bg">
      <box class="grid grid-cols-1 grid-rows-2 width-full height-full overflow-hidden">
        <box class="inline width-full height-full overflow-hidden">
          <.sidebar
            active={@active}
            screen_text={@screen_text}
            snapshots={@snapshots}
            latest_source_text={@latest_source_text}
            active_selected_text={@active_selected_text}
            active_hovered_text={@active_hovered_text}
            active_focused_text={@active_focused_text}
            active_focusables_text={@active_focusables_text}
            active_component_module_text={@active_component_module_text}
            active_component_function_text={@active_component_function_text}
            source_entries={@source_entries}
          />
          <box class="width-full bg height-full padding-left-1 overflow-hidden">
            <.tabs
              id="remote-inspector-tabs"
              selected={@panel_tab}
              highlight="primary"
              br-change="tab_changed"
              class="width-full height-full border-rounded bg"
              item_class="width-9"
            >
              <:tab value="tree" label="Tree">
                <.tree_tab
                  active={@active}
                  nodes={@active_render_tree_nodes}
                  selected={@active_render_tree_selected}
                  expanded={@active_render_tree_expanded}
                  kind={@render_tree_kind}
                />
              </:tab>
              <:tab value="overview" label="Overview">
                <.overview_tab
                  scroll_id="remote-inspector-tabs-panel-overview"
                  active={@active}
                  active_source_text={@active_source_text}
                  active_theme_text={@active_theme_text}
                  active_status_text={@active_status_text}
                  active_counts_text={@active_counts_text}
                  active_layout_text={@active_layout_text}
                  active_box_text={@active_box_text}
                  active_component_text={@active_component_text}
                  active_class_text={@active_class_text}
                  active_style_input_text={@active_style_input_text}
                  active_color_text={@active_color_text}
                  show_fg_swatch={@show_fg_swatch?}
                  show_bg_swatch={@show_bg_swatch?}
                  fg_swatch_style={@fg_swatch_style}
                  bg_swatch_style={@bg_swatch_style}
                  active_fragment_text={@active_fragment_text}
                  active_fragment_render={@active_fragment_render}
                />
              </:tab>
              <:tab value="layout" label="Element">
                <.layout_tab
                  scroll_id="remote-inspector-tabs-panel-layout"
                  active={@active}
                  layout_data={@active_layout_data}
                  flag_rows={@active_flag_rows}
                  active_focus_text={@active_focus_text}
                  active_selected_focus_text={@active_selected_focus_text}
                />
              </:tab>
              <:tab value="theme" label="Theme">
                <.theme_tab
                  scroll_id="remote-inspector-tabs-panel-theme"
                  active={@active}
                  active_theme_text={@active_theme_text}
                  rows={@active_theme_rows}
                />
              </:tab>
              <:tab value="implicit" label="Implicit">
                <.implicit_tab
                  scroll_id="remote-inspector-tabs-panel-implicit"
                  active={@active}
                  active_implicit_text={@active_implicit_text}
                  active_implicit_detail_text={@active_implicit_detail_text}
                />
              </:tab>
            </.tabs>
          </box>
        </box>
        <box class="height-1 width-full overflow-hidden bg-emphasize-12">
          <.keybinding_bar
            keybindings={@breeze.keybindings}
            class="inline width-full height-1 overflow-hidden bg-emphasize-12 padding-left-1 padding-right-1"
          />
        </box>
      </box>
    </box>
    """
  end

  attr :active, :any, required: true
  attr :screen_text, :string, required: true
  attr :snapshots, :map, required: true
  attr :latest_source_text, :string, required: true
  attr :active_selected_text, :string, required: true
  attr :active_hovered_text, :string, required: true
  attr :active_focused_text, :string, required: true
  attr :active_focusables_text, :string, required: true
  attr :active_component_module_text, :string, required: true
  attr :active_component_function_text, :string, required: true
  attr :source_entries, :list, required: true

  def sidebar(assigns) do
    ~H"""
    <box class="width-32 height-full border-rounded overflow-hidden bg padding-right-1">
      <box class="width-full bold text-primary">Remote Inspector</box>
      <box class="width-full text-muted">screen={@screen_text}</box>
      <box class="width-full text-muted">sources={map_size(@snapshots)}</box>
      <box class="width-full text-muted">latest={@latest_source_text}</box>
      <box class="width-full">
      </box>
      <box :if={!is_nil(@active)} class="width-full bold text-primary">SELECTED</box>
      <box :if={!is_nil(@active)} class="width-full text-muted">{@active_selected_text}</box>
      <box :if={!is_nil(@active)} class="width-full">
      </box>
      <box :if={!is_nil(@active)} class="width-full bold text-primary">HOVER</box>
      <box :if={!is_nil(@active)} class="width-full text-muted">{@active_hovered_text}</box>
      <box :if={!is_nil(@active)} class="width-full">
      </box>
      <box :if={!is_nil(@active)} class="width-full bold text-primary">FOCUSED</box>
      <box :if={!is_nil(@active)} class="width-full text-muted">{@active_focused_text}</box>
      <box :if={!is_nil(@active)} class="width-full text-muted">({@active_focusables_text})</box>
      <box
        :if={!is_nil(@active) and
      (@active_component_module_text != "-" or @active_component_function_text != "-")}
        class="width-full"
      >
      </box>
      <box
        :if={!is_nil(@active) and @active_component_module_text != "-"}
        class="width-full bold text-primary"
      >
        MODULE
      </box>
      <box
        :if={!is_nil(@active) and @active_component_module_text != "-"}
        class="width-full text-muted"
      >
        {@active_component_module_text}
      </box>
      <box :if={!is_nil(@active) and @active_component_function_text != "-"} class="width-full">
      </box>
      <box
        :if={!is_nil(@active) and @active_component_function_text != "-"}
        class="width-full bold text-primary"
      >
        FUNCTION
      </box>
      <box
        :if={!is_nil(@active) and @active_component_function_text != "-"}
        class="width-full text-muted"
      >
        {@active_component_function_text}
      </box>
      <box :if={is_nil(@active)} class="width-full text-muted">
        Waiting for remote inspector snapshots...
      </box>
      <box class="width-full">
      </box>
      <box class="width-full bold">Sources</box>
      <box class="height-full overflow-hidden">
        <box :for={entry <- @source_entries} class="width-full height-6">
          <box class={entry.label_class}>node</box>
          <box class={entry.node_class}>{entry.node}</box>
          <box class="width-full">
          </box>
          <box class={entry.label_class}>pid</box>
          <box class={entry.pid_class}>{entry.pid}</box>
          <box class="width-full">
          </box>
        </box>
      </box>
    </box>
    """
  end

  attr :active, :any, required: true
  attr :nodes, :list, required: true
  attr :selected, :any, required: true
  attr :expanded, :list, required: true
  attr :kind, :string, required: true

  def tree_tab(assigns) do
    ~H"""
    <box class="width-full height-full padding-top-1">
      <box :if={!is_nil(@active)} class="width-full text-muted">tree={@kind}</box>
      <.tree
        :if={!is_nil(@active) and @nodes != []}
        id="remote-inspector-render-tree"
        nodes={@nodes}
        selected={@selected}
        expanded={@expanded}
        collapsed_prefix="▸"
        expanded_prefix="▾"
        virtual
        br-change="render_tree_changed"
        class="width-full height-full bg"
      />
      <box :if={is_nil(@active) or @nodes == []} class="width-full text-muted">
        Waiting for render tree...
      </box>
    </box>
    """
  end

  attr :active, :any, required: true
  attr :scroll_id, :string, required: true
  attr :active_source_text, :string, required: true
  attr :active_theme_text, :string, required: true
  attr :active_status_text, :string, required: true
  attr :active_counts_text, :string, required: true
  attr :active_layout_text, :string, required: true
  attr :active_box_text, :string, required: true
  attr :active_component_text, :string, required: true
  attr :active_class_text, :string, required: true
  attr :active_style_input_text, :string, required: true
  attr :active_color_text, :string, required: true
  attr :show_fg_swatch, :boolean, required: true
  attr :show_bg_swatch, :boolean, required: true
  attr :fg_swatch_style, :map, required: true
  attr :bg_swatch_style, :map, required: true
  attr :active_fragment_text, :string, required: true
  attr :active_fragment_render, :string, required: true

  def overview_tab(assigns) do
    ~H"""
    <.scroll id={@scroll_id} class="width-full height-full padding-top-1">
      <box class="width-full">
        <box :if={!is_nil(@active)} class="width-full text-muted">source={@active_source_text}</box>
        <box :if={!is_nil(@active)} class="width-full text-muted">theme={@active_theme_text}</box>
        <box :if={!is_nil(@active)} class="width-full text-muted">status={@active_status_text}</box>
        <box :if={!is_nil(@active)} class="width-full text-muted">counts={@active_counts_text}</box>
        <box :if={!is_nil(@active)} class="width-full">layout={@active_layout_text}</box>
        <box :if={!is_nil(@active)} class="width-full">box={@active_box_text}</box>
        <box :if={!is_nil(@active) and @active_component_text != "-"} class="width-full text-muted">
          component={@active_component_text}
        </box>
        <box :if={!is_nil(@active)} class="width-full">class={@active_class_text}</box>
        <box :if={!is_nil(@active) and @active_style_input_text != "-"} class="width-full text-muted">
          style_input={@active_style_input_text}
        </box>
        <box :if={!is_nil(@active)} class="inline width-full">
          <box>colors={@active_color_text}</box>
          <box :if={@show_fg_swatch}>
          </box>
          <box :if={@show_fg_swatch} style={@fg_swatch_style}>██</box>
          <box :if={@show_bg_swatch}>
          </box>
          <box :if={@show_bg_swatch} style={@bg_swatch_style}>██</box>
        </box>
        <box :if={!is_nil(@active)} class="width-full text-muted">
          fragment={@active_fragment_text}
        </box>
        <box :if={!is_nil(@active) and @active_fragment_render != ""} class="width-full text-muted">
          fragment_render=
        </box>
        <box
          :if={!is_nil(@active) and @active_fragment_render != ""}
          class="width-full height-3 overflow-hidden"
        >
          {@active_fragment_render}
        </box>
      </box>
    </.scroll>
    """
  end

  attr :active, :any, required: true
  attr :scroll_id, :string, required: true
  attr :layout_data, :any, required: true
  attr :flag_rows, :list, required: true
  attr :active_focus_text, :string, required: true
  attr :active_selected_focus_text, :string, required: true

  def layout_tab(assigns) do
    ~H"""
    <.scroll id={@scroll_id} class="width-full height-full padding-top-1">
      <box class="width-full">
        <.section :if={!is_nil(@active) and @layout_data} title="Frame">
          <.kv_row label="position" value={@layout_data.frame.position}/>
          <.kv_row label="bounds" value={@layout_data.frame.bounds} muted/>
        </.section>
        <box :if={!is_nil(@active) and @layout_data} class="width-full">
        </box>
        <.section :if={!is_nil(@active) and @layout_data} title="Box">
          <.kv_row label="viewport" value={@layout_data.box.viewport}/>
          <.kv_row label="padded" value={@layout_data.box.padded}/>
          <.kv_row label="content" value={@layout_data.box.content}/>
          <.kv_row label="padding" value={@layout_data.box.padding} muted/>
          <.kv_row label="scroll" value={@layout_data.box.scroll} muted/>
        </.section>
        <box :if={!is_nil(@active) and @layout_data} class="width-full">
        </box>
        <.section :if={!is_nil(@active)} title="Focus">
          <.kv_row label="global" value={@active_focus_text}/>
          <.kv_row
            :if={@active_selected_focus_text != "-"}
            label="selected"
            value={@active_selected_focus_text}
            muted
          />
        </.section>
        <box :if={!is_nil(@active) and @layout_data} class="width-full">
        </box>
        <.section :if={!is_nil(@active) and @layout_data} title="Size">
          <.box_model_preview preview={@layout_data.preview}/>
        </.section>
        <box :if={!is_nil(@active) and @flag_rows != []} class="width-full">
        </box>
        <.section :if={!is_nil(@active) and @flag_rows != []} title="Attributes">
          <box :for={row <- @flag_rows} class="width-full overflow-hidden text-muted">{row}</box>
        </.section>
      </box>
    </.scroll>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :muted, :boolean, default: false

  def kv_row(assigns) do
    ~H"""
    <box class={if @muted do
      "inline width-full text-muted"
    else
      "inline width-full"
    end}>
      <box class="width-10">{@label}</box>
      <box class="width-full overflow-hidden">{@value}</box>
    </box>
    """
  end

  attr :preview, :map, required: true

  def box_model_preview(assigns) do
    ~H"""
    <box class="width-44 height-7 overflow-hidden">
      <box class={@preview.outer_class} style={@preview.outer_style}>
        <box style={@preview.label_row_style}>{@preview.top_label}</box>
        <box class="inline width-full" style={@preview.middle_row_style}>
          <box style={@preview.side_column_style}>
            <box style={@preview.side_label_style}>{@preview.left_label}</box>
          </box>
          <box class={@preview.inner_class} style={@preview.inner_style}>
            <box style={@preview.content_label_style}>{@preview.content_label}</box>
          </box>
          <box style={@preview.side_column_style}>
            <box style={@preview.side_label_style}>{@preview.right_label}</box>
          </box>
        </box>
        <box style={@preview.label_row_style}>{@preview.bottom_label}</box>
      </box>
    </box>
    <box class="width-full overflow-hidden text-muted">{@preview.viewport_label}</box>
    """
  end

  attr :active, :any, required: true
  attr :scroll_id, :string, required: true
  attr :active_theme_text, :string, required: true
  attr :rows, :list, required: true

  def theme_tab(assigns) do
    ~H"""
    <.scroll id={@scroll_id} class="width-full height-full padding-top-1">
      <box class="width-full">
        <box :if={!is_nil(@active)} class="width-full text-muted">theme={@active_theme_text}</box>
        <box :if={!is_nil(@active)} class="width-full">
        </box>
        <box
          :for={row <- @rows}
          :if={!is_nil(@active)}
          class={row.class}
          style={Map.get(row, :style)}
        >
          {row.text}
        </box>
      </box>
    </.scroll>
    """
  end

  attr :active, :any, required: true
  attr :scroll_id, :string, required: true
  attr :active_implicit_text, :string, required: true
  attr :active_implicit_detail_text, :string, required: true

  def implicit_tab(assigns) do
    ~H"""
    <.scroll id={@scroll_id} class="width-full height-full padding-top-1">
      <box class="width-full">
        <box :if={!is_nil(@active)} class="width-full">implicit={@active_implicit_text}</box>
        <box
          :if={!is_nil(@active) and @active_implicit_detail_text != "-"}
          class="width-full text-muted"
        >
          implicit_details={@active_implicit_detail_text}
        </box>
      </box>
    </.scroll>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <box class="width-full">
      <box class="width-full bold text-primary">{@title}</box>
      {render_slot(@inner_block)}
    </box>
    """
  end

  def handle_info(
        {:remote_inspector, %{snapshots: snapshots, latest_source: latest_source}},
        term
      ) do
    active_source = normalize_active_source(term.assigns.active_source, snapshots, latest_source)

    term =
      term
      |> assign(
        snapshots: snapshots,
        latest_source: latest_source,
        active_source: active_source
      )
      |> refresh_active_render_tree()

    {:noreply, term}
  end

  def handle_info(:resize, term) do
    {:noreply, assign(term, screen: term.terminal.size)}
  end

  def handle_event("tab_changed", %{value: value}, term) do
    {:noreply,
     term
     |> assign(panel_tab: value)
     |> put_tree_keybindings()
     |> refresh_active_render_tree(force: value == "tree")}
  end

  def handle_event("tab_changed", %{"value" => value}, term) do
    {:noreply,
     term
     |> assign(panel_tab: value)
     |> put_tree_keybindings()
     |> refresh_active_render_tree(force: value == "tree")}
  end

  def handle_event("render_tree_changed", payload, term) do
    selected = payload_value(payload, :value)
    expanded = normalize_expanded(payload_value(payload, :expanded))
    active_source = active_source(term.assigns)
    active = active_entry(term.assigns)
    kind = render_tree_kind(term.assigns)
    current_tree = active_render_tree(term.assigns, active_source, active, kind)
    selection_changed? = render_tree_selection_changed?(current_tree, active, selected)

    expansion_changed? =
      render_tree_expansion_changed?(term.assigns, active_source, kind, expanded)

    if selection_changed? or expansion_changed? do
      select_remote_element(active, selected)

      render_tree_expanded =
        if active_source && is_list(expanded) do
          term.assigns
          |> Map.get(:render_tree_expanded, %{})
          |> Map.put(render_tree_cache_key(active_source, kind), expanded)
        else
          Map.get(term.assigns, :render_tree_expanded, %{})
        end

      term =
        term
        |> assign(render_tree_expanded: render_tree_expanded)
        |> refresh_active_render_tree(selected_id: selected, force: true)

      {:noreply, term}
    else
      {:noreply, term}
    end
  end

  def handle_event(_, %{"key" => key}, term) when key in ["t", "T"] do
    {:noreply, toggle_tree_panel(term)}
  end

  def handle_event(_, %{"key" => "q"}, term), do: quit(%{"key" => "q"}, term)
  def handle_event(_, _, term), do: {:noreply, term}

  defp active_source(assigns),
    do: Map.get(assigns, :active_source) || Map.get(assigns, :latest_source)

  defp active_entry(%{snapshots: snapshots, latest_source: latest_source} = assigns) do
    Map.get(snapshots, active_source(assigns) || latest_source)
  end

  defp payload_value(payload, key) when is_map(payload) do
    Map.get(payload, key) || Map.get(payload, Atom.to_string(key))
  end

  defp payload_value(_payload, _key), do: nil

  defp normalize_expanded(nil), do: nil
  defp normalize_expanded(expanded) when is_list(expanded), do: expanded
  defp normalize_expanded(expanded), do: List.wrap(expanded)

  defp put_tree_keybindings(term) do
    put_local_keybindings(term, tree_keybindings(term.assigns))
  end

  defp tree_keybindings(%{panel_tab: "tree"} = assigns) do
    [
      {"t", tree_keybinding_label(render_tree_kind(assigns)),
       fn _event, term ->
         {:noreply, toggle_tree_panel(term)}
       end}
    ]
  end

  defp tree_keybindings(_assigns), do: []

  defp tree_keybinding_label("code"), do: "Rendered tree"
  defp tree_keybinding_label(_kind), do: "Code tree"

  defp toggle_tree_panel(term) do
    next_kind =
      if Map.get(term.assigns, :panel_tab) == "tree" do
        next_render_tree_kind(render_tree_kind(term.assigns))
      else
        render_tree_kind(term.assigns)
      end

    term
    |> assign(panel_tab: "tree", render_tree_kind: next_kind)
    |> put_tree_keybindings()
    |> refresh_active_render_tree(force: true)
  end

  defp render_tree_kind(%{render_tree_kind: kind}), do: normalize_render_tree_kind(kind)
  defp render_tree_kind(_assigns), do: "rendered"

  defp normalize_render_tree_kind(kind) when kind in [:code, "code"], do: "code"
  defp normalize_render_tree_kind(_kind), do: "rendered"

  defp next_render_tree_kind("rendered"), do: "code"
  defp next_render_tree_kind(_kind), do: "rendered"

  defp render_tree_kind_atom("code"), do: :code
  defp render_tree_kind_atom(_kind), do: :rendered

  defp render_tree_cache_key(source, "rendered"), do: source
  defp render_tree_cache_key(source, kind), do: {source, kind}

  defp render_tree_selection_changed?(_tree, _active, selected) when not is_binary(selected),
    do: false

  defp render_tree_selection_changed?(tree, active, selected) do
    current =
      case tree do
        %{selected_id: selected_id} -> selected_id
        _ -> get_in(active || %{}, [:snapshot, :selected_id])
      end

    selected != current
  end

  defp render_tree_expansion_changed?(_assigns, _source, _kind, expanded)
       when not is_list(expanded),
       do: false

  defp render_tree_expansion_changed?(assigns, source, kind, expanded) do
    current =
      assigns
      |> Map.get(:render_tree_expanded, %{})
      |> Map.get(render_tree_cache_key(source, kind), [])

    expanded != current
  end

  defp select_remote_element(_active, selected) when not is_binary(selected), do: :ok

  defp select_remote_element(%{snapshot: %{source: %{server_pid: pid}}}, selected)
       when is_pid(pid) do
    Breeze.Server.select_inspector(pid, selected)
  end

  defp select_remote_element(%{source: %{pid: pid}}, selected) when is_pid(pid) do
    Breeze.Server.select_inspector(pid, selected)
  end

  defp select_remote_element(_active, _selected), do: :ok

  defp refresh_active_render_tree(term, opts \\ []) do
    if Keyword.get(opts, :force, false) or Map.get(term.assigns, :panel_tab) == "tree" do
      active_source = active_source(term.assigns)
      active = active_entry(term.assigns)
      kind = render_tree_kind(term.assigns)

      case fetch_render_tree(active, term.assigns, active_source, kind, opts) do
        nil ->
          term

        tree ->
          cache_key = render_tree_cache_key(active_source, kind)

          render_trees =
            term.assigns
            |> Map.get(:render_trees, %{})
            |> Map.put(cache_key, tree)

          render_tree_expanded =
            term.assigns
            |> Map.get(:render_tree_expanded, %{})
            |> Map.put(cache_key, Map.get(tree, :expanded, []))

          assign(term, render_trees: render_trees, render_tree_expanded: render_tree_expanded)
      end
    else
      term
    end
  end

  defp fetch_render_tree(nil, _assigns, _source, _kind, _opts), do: nil
  defp fetch_render_tree(_active, _assigns, nil, _kind, _opts), do: nil

  defp fetch_render_tree(active, assigns, source, kind, opts) do
    expanded =
      opts[:expanded] ||
        assigns
        |> Map.get(:render_tree_expanded, %{})
        |> Map.get(render_tree_cache_key(source, kind), [])

    selected_id = opts[:selected_id] || active.snapshot.selected_id

    case source_server_pid(active) do
      pid when is_pid(pid) ->
        Breeze.Server.inspector_render_tree(pid,
          expanded: expanded,
          selected_id: selected_id,
          kind: render_tree_kind_atom(kind),
          limit: @render_tree_limit
        )

      _ ->
        snapshot_render_tree(active.snapshot, kind)
    end
  catch
    :exit, _reason -> snapshot_render_tree(active.snapshot, kind)
  end

  defp source_server_pid(%{snapshot: %{source: %{server_pid: pid}}}) when is_pid(pid), do: pid
  defp source_server_pid(%{source: %{pid: pid}}) when is_pid(pid), do: pid
  defp source_server_pid(_active), do: nil

  defp active_render_tree(assigns, source, active, kind) do
    assigns
    |> Map.get(:render_trees, %{})
    |> Map.get(render_tree_cache_key(source, kind))
    |> case do
      nil -> if(active, do: snapshot_render_tree(active.snapshot, kind), else: nil)
      tree -> tree
    end
  end

  defp snapshot_render_tree(snapshot, kind)
  defp snapshot_render_tree(_snapshot, "code"), do: nil

  defp snapshot_render_tree(%{render_tree: tree, selected_id: selected_id}, _kind)
       when is_map(tree) do
    %{
      nodes: [tree],
      selected_id: selected_id,
      expanded: default_render_tree_expanded(tree, selected_id),
      limit: @render_tree_limit,
      truncated?: false
    }
  end

  defp snapshot_render_tree(_snapshot, _kind), do: nil

  defp render_tree_nodes(%{nodes: nodes}) when is_list(nodes) do
    Enum.map(nodes, &colorize_render_tree_node/1)
  end

  defp render_tree_nodes(_tree), do: []

  defp colorize_render_tree_node(%{} = node) do
    node
    |> Map.update(:label, Map.get(node, :id, ""), fn label ->
      case Map.get(node, :label_parts) do
        parts when is_list(parts) -> render_tree_label_spans(parts)
        _ -> label
      end
    end)
    |> Map.update(:children, [], fn children ->
      children
      |> List.wrap()
      |> Enum.map(&colorize_render_tree_node/1)
    end)
  end

  defp colorize_render_tree_node(node), do: node

  defp render_tree_label_spans(parts) do
    parts
    |> Enum.map(fn part ->
      TextSpan.new(to_string(Map.get(part, :text, "")), render_tree_label_style(part))
    end)
    |> Enum.reject(&(&1.text == ""))
  end

  defp render_tree_label_style(%{token: :punctuation}), do: %{foreground_color: 8}
  defp render_tree_label_style(%{token: :tag}), do: %{foreground_color: 14}
  defp render_tree_label_style(%{token: :id}), do: %{foreground_color: 11}
  defp render_tree_label_style(%{token: :anonymous_id}), do: %{foreground_color: 8}
  defp render_tree_label_style(%{token: :class}), do: %{foreground_color: 10}
  defp render_tree_label_style(%{token: :component}), do: %{foreground_color: 8}
  defp render_tree_label_style(%{token: :separator}), do: %{}

  defp render_tree_label_style(%{token: :swatch} = part) do
    %{}
    |> put_swatch_color(:foreground_color, Map.get(part, :foreground_color))
    |> put_swatch_color(:background_color, Map.get(part, :background_color))
  end

  defp render_tree_label_style(_part), do: %{}

  defp put_swatch_color(style, _key, nil), do: style
  defp put_swatch_color(style, key, color), do: Map.put(style, key, color)

  defp render_tree_selected(%{selected_id: selected_id}, _snapshot), do: selected_id
  defp render_tree_selected(_tree, snapshot), do: Map.get(snapshot, :selected_id)

  defp render_tree_expanded(%{expanded: expanded}) when is_list(expanded), do: expanded
  defp render_tree_expanded(_tree), do: []

  defp default_render_tree_expanded(nil, _selected_id), do: []

  defp default_render_tree_expanded(tree, selected_id) do
    case render_tree_path(tree, selected_id) do
      [] ->
        expandable_tree_id(tree)

      path ->
        expanded = Enum.drop(path, -1)

        case expanded do
          [] -> expandable_tree_id(tree)
          _ -> expanded
        end
    end
  end

  defp expandable_tree_id(%{id: id, children: [_ | _]}), do: [id]
  defp expandable_tree_id(_tree), do: []

  defp render_tree_path(_tree, selected_id) when not is_binary(selected_id), do: []

  defp render_tree_path(%{id: selected_id}, selected_id), do: [selected_id]

  defp render_tree_path(%{id: id, children: children}, selected_id) when is_list(children) do
    Enum.find_value(children, [], fn child ->
      case render_tree_path(child, selected_id) do
        [] -> nil
        path -> [id | path]
      end
    end)
  end

  defp render_tree_path(_tree, _selected_id), do: []

  defp label(nil, fallback), do: fallback || "-"

  defp label(%{actual_id: actual_id, flags: flags}, fallback) do
    cond do
      is_binary(actual_id) -> actual_id
      true -> "anon##{Map.get(flags, :__inspector_idx__, fallback || "-")}"
    end
  end

  defp format_source(nil), do: "-"
  defp format_source({node, pid}), do: "#{node}:#{pid}"
  defp format_source(%{node: node, pid: pid}), do: "#{node}:#{inspect(pid)}"

  defp format_server(%{source: %{node: node, server_pid: server_pid, view_pid: view_pid}}) do
    "node=#{node} server=#{inspect(server_pid)} view=#{inspect(view_pid)}"
  end

  defp format_server(_snapshot), do: "-"

  defp format_theme(nil), do: "-"

  defp format_theme(theme) do
    probe =
      case Breeze.Theme.probe_status(theme) do
        nil -> nil
        status -> " probe=#{status}"
      end

    "#{theme.name || "-"} mode=#{theme.mode} dark=#{inspect(theme.dark)}#{probe}"
  end

  defp format_screen(%{width: width, height: height}), do: "#{width}x#{height}"
  defp format_screen(_screen), do: "-"

  defp theme_rows(nil), do: []

  defp theme_rows(theme) do
    label_width =
      [theme.defaults, theme.palette, theme.extras]
      |> Enum.flat_map(fn values ->
        if is_map(values), do: Map.keys(values), else: []
      end)
      |> Enum.map(&(&1 |> to_string() |> String.length()))
      |> case do
        [] -> 0
        lengths -> Enum.max(lengths)
      end

    []
    |> append_theme_rows("Defaults", theme.defaults, label_width)
    |> append_theme_rows("Palette", theme.palette, label_width)
    |> append_theme_rows("Extras", theme.extras, label_width)
  end

  defp append_theme_rows(rows, _label, values, _label_width)
       when not is_map(values) or map_size(values) == 0,
       do: rows

  defp append_theme_rows(rows, label, values, label_width) do
    entry_rows =
      values
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.flat_map(fn {key, value} ->
        key_text =
          key
          |> to_string()
          |> String.pad_trailing(label_width)

        [
          %{
            class: "width-full overflow-hidden text-muted",
            text: "#{key_text} #{fmt_color(value)}"
          },
          %{
            class: "width-full overflow-hidden",
            style: %{foreground_color: value},
            text: "████████████████████████████████"
          }
        ]
      end)

    spacer =
      case rows do
        [] -> []
        _ -> [%{class: "width-full", text: ""}]
      end

    rows ++ spacer ++ [%{class: "width-full bold text-primary", text: label}] ++ entry_rows
  end

  defp source_entries(snapshots, active_source) do
    snapshots
    |> Enum.sort_by(fn {key, entry} -> {key != active_source, -entry.updated_at} end)
    |> Enum.map(fn {key, entry} ->
      %{
        active?: key == active_source,
        alive?: Map.get(entry, :alive?, true),
        label_class: source_label_class(key == active_source, Map.get(entry, :alive?, true)),
        node_class: source_node_class(key == active_source, Map.get(entry, :alive?, true)),
        pid_class: source_pid_class(key == active_source, Map.get(entry, :alive?, true)),
        node: source_node(entry),
        pid: source_pid(entry)
      }
    end)
  end

  defp source_node(%{source: source}), do: to_string(source.node)
  defp source_pid(%{source: source}), do: inspect(source.pid)

  defp source_label_class(_active?, false), do: "width-full text-error bold"
  defp source_label_class(true, true), do: "width-full text-primary bold"
  defp source_label_class(false, true), do: "width-full text-muted"

  defp source_node_class(_active?, false), do: "width-full text-error"
  defp source_node_class(true, true), do: "width-full text-primary"
  defp source_node_class(false, true), do: "width-full text-muted"

  defp source_pid_class(_active?, false), do: "width-full text-muted"
  defp source_pid_class(true, true), do: "width-full text-primary"
  defp source_pid_class(false, true), do: "width-full text-muted"

  defp layout_data(nil), do: nil

  defp layout_data(
         %{
           viewport: viewport,
           bounds: bounds,
           content_box: content_box,
           padding: padding,
           scroll: scroll
         } = selected
       ) do
    padded_width = padded_width(selected)
    padded_height = padded_height(selected)

    %{
      frame: %{
        position:
          "left=#{viewport.left} top=#{viewport.top} width=#{viewport.width || 0} height=#{viewport.height}",
        bounds: fmt_bounds(bounds)
      },
      box: %{
        viewport: "#{viewport.viewport_width || 0}x#{viewport.viewport_height}",
        padded: "#{padded_width}x#{padded_height}",
        content: "#{content_box.width}x#{content_box.height}",
        padding: fmt_padding(padding),
        scroll: inspect(scroll || {0, 0})
      },
      preview: box_model_preview_data(selected)
    }
  end

  defp box_model_preview_data(%{
         viewport: viewport,
         style: style,
         content_box: content_box,
         padding: padding
       }) do
    resolved_border = Map.get(style || %{}, :border, %{})
    border? = border_present?(resolved_border)
    border = if border?, do: resolved_border, else: dashed_border()
    width = 43
    outer_border_vertical = border_vertical_inset(border)
    outer_border_horizontal = border_horizontal_inset(border)
    side_column_width = max(max(label_width(padding.left), label_width(padding.right)), 3)
    inner_width = max(width - side_column_width * 2 - outer_border_horizontal, 3)
    inner_border = preview_content_border()
    inner_border_horizontal = border_horizontal_inset(inner_border)
    outer_inner_width = max(width - outer_border_horizontal, 1)
    content_label_width = max(inner_width - inner_border_horizontal, 1)

    %{
      outer_class:
        if(border?, do: "border-primary text-primary", else: "border-muted text-muted"),
      outer_style: %{
        width: width,
        height: 5 + outer_border_vertical,
        border: border,
        overflow: :hidden
      },
      label_row_style: %{
        width: outer_inner_width,
        height: 1,
        text_align: :center,
        overflow: :hidden
      },
      middle_row_style: %{
        width: outer_inner_width,
        height: 3,
        overflow: :hidden
      },
      side_column_style: %{
        width: side_column_width,
        height: 3,
        padding_top: 1,
        padding_bottom: 1,
        overflow: :hidden
      },
      side_label_style: %{
        width: side_column_width,
        height: 1,
        text_align: :center,
        overflow: :hidden
      },
      inner_class: "text-muted",
      inner_style: %{
        width: inner_width,
        height: 3,
        border: inner_border,
        overflow: :hidden
      },
      content_label_style: %{
        width: content_label_width,
        height: 1,
        text_align: :center,
        overflow: :hidden
      },
      top_label: to_string(padding.top),
      right_label: to_string(padding.right),
      bottom_label: to_string(padding.bottom),
      left_label: to_string(padding.left),
      content_label: "#{content_box.width}x#{content_box.height}",
      viewport_label: "viewport #{viewport.viewport_width || 0}x#{viewport.viewport_height}"
    }
  end

  defp border_present?(border) when is_map(border) do
    Enum.any?([:top, :right, :bottom, :left], &Map.get(border, &1))
  end

  defp border_present?(_border), do: false

  defp border_vertical_inset(border) do
    top = if Map.get(border, :top), do: 1, else: 0
    bottom = if Map.get(border, :bottom), do: 1, else: 0
    top + bottom
  end

  defp border_horizontal_inset(border) do
    left = if Map.get(border, :left), do: 1, else: 0
    right = if Map.get(border, :right), do: 1, else: 0
    left + right
  end

  defp preview_content_border do
    BackBreeze.Border.custom(%{
      top_left: "┌",
      top_right: "┐",
      bottom_left: "└",
      bottom_right: "┘",
      left: "│",
      right: "│",
      top: "─",
      bottom: "─"
    })
  end

  defp label_width(value) when is_integer(value),
    do: value |> Integer.to_string() |> String.length()

  defp label_width(value), do: value |> to_string() |> String.length()

  defp padded_width(%{viewport: viewport, content_box: content_box, padding: padding}) do
    min(viewport.width || 0, content_box.width + padding.left + padding.right)
  end

  defp padded_height(%{viewport: viewport, content_box: content_box, padding: padding}) do
    min(viewport.height, content_box.height + padding.top + padding.bottom)
  end

  defp dashed_border do
    BackBreeze.Border.custom(%{
      top_left: "┏",
      top_right: "┓",
      bottom_left: "┗",
      bottom_right: "┛",
      left: "╏",
      right: "╏",
      top: "╍",
      bottom: "╍"
    })
    |> Map.put(:horizontal, "╍")
  end

  defp layout_line(nil), do: "-"

  defp layout_line(%{viewport: viewport, bounds: bounds}) do
    "left=#{viewport.left} top=#{viewport.top} width=#{viewport.width || 0} height=#{viewport.height} bounds=#{fmt_bounds(bounds)}"
  end

  defp box_line(nil), do: "-"

  defp box_line(%{viewport: viewport, content_box: content_box, padding: padding, scroll: scroll}) do
    "viewport=#{viewport.viewport_width || 0}x#{viewport.viewport_height} content=#{viewport.content_width || 0}x#{viewport.content_height} inner=#{content_box.width}x#{content_box.height} padding=#{fmt_padding(padding)} scroll=#{inspect(scroll || {0, 0})}"
  end

  defp class_line(nil), do: "-"
  defp class_line(%{class: nil}), do: "-"
  defp class_line(%{class: class}), do: class

  defp component_line(nil), do: "-"
  defp component_line(%{component: nil}), do: "-"
  defp component_line(%{component: component}), do: component

  defp component_module_line(nil), do: "-"
  defp component_module_line(%{component: nil}), do: "-"

  defp component_module_line(%{component: component}) do
    case split_component(component) do
      {mod, _fun} -> mod
      _ -> component
    end
  end

  defp component_function_line(nil), do: "-"
  defp component_function_line(%{component: nil}), do: "-"

  defp component_function_line(%{component: component}) do
    case split_component(component) do
      {_mod, fun} -> fun
      _ -> "-"
    end
  end

  defp split_component(component) when is_binary(component) do
    parts = String.split(component, ".")

    case Enum.split(parts, length(parts) - 1) do
      {[], _} -> nil
      {mod_parts, [fun]} -> {Enum.join(mod_parts, "."), fun}
      _ -> nil
    end
  end

  defp split_component(_component), do: nil

  defp style_input_line(nil), do: "-"
  defp style_input_line(%{style_input: nil}), do: "-"
  defp style_input_line(%{style_input: style_input}), do: compact_inspect(style_input, 120)

  defp color_line(nil), do: "fg=- bg=-"

  defp color_line(%{style: style}) do
    "fg=#{fmt_color(Map.get(style, :foreground_color))} bg=#{fmt_color(Map.get(style, :background_color))}"
  end

  defp show_color_swatch?(nil, _key), do: false

  defp show_color_swatch?(%{snapshot: %{selected: %{style: style}}}, key) do
    not is_nil(Map.get(style, key))
  end

  defp show_color_swatch?(_, _key), do: false

  defp swatch_style(nil, _key), do: %{foreground_color: 7}

  defp swatch_style(%{snapshot: %{selected: %{style: style}}}, key) do
    color = Map.get(style, key)
    %{foreground_color: color}
  end

  defp swatch_style(_, _key), do: %{foreground_color: 7}

  defp implicit_line(nil), do: "-"

  defp implicit_line(%{
         implicit_module: mod,
         implicit_state: implicit_state,
         implicit_meta: implicit_meta
       }) do
    "mod=#{inspect(mod)} state=#{compact_inspect(implicit_state, 80)} meta=#{compact_inspect(implicit_meta, 60)}"
  end

  defp implicit_detail_line(nil), do: "-"
  defp implicit_detail_line(%{implicit_state: nil}), do: "-"

  defp implicit_detail_line(%{implicit_state: implicit_state}) when is_map(implicit_state) do
    details =
      []
      |> maybe_detail("cursor", Map.get(implicit_state, :cursor))
      |> maybe_detail("value_len", string_length(Map.get(implicit_state, :value)))
      |> maybe_detail("placeholder", present_string(Map.get(implicit_state, :placeholder)))
      |> maybe_detail("selected_index", Map.get(implicit_state, :selected_index))
      |> maybe_detail("highlighted_index", Map.get(implicit_state, :highlighted_index))
      |> maybe_detail("open?", Map.get(implicit_state, :open?))

    case details do
      [] -> "-"
      _ -> Enum.join(details, " ")
    end
  end

  defp implicit_detail_line(_selected), do: "-"

  defp focus_line(%{focused: focused, focus: focus}) do
    "active_scope=#{inspect(focus.active_scope)} focusables=#{length(focus.focusables)} memory=#{compact_inspect(focus.focus_memory, 80)} focused=#{focused || "-"}"
  end

  defp focus_line(_snapshot), do: "-"

  defp focusables_summary(%{focus: focus}) do
    "#{length(focus.focusables)} focusables"
  end

  defp focusables_summary(_snapshot), do: "0 focusables"

  defp selected_focus_line(nil), do: "-"

  defp selected_focus_line(
         %{flags: flags, focus_meta: focus_meta, focus_path: focus_path} = selected
       ) do
    details =
      []
      |> maybe_detail("focusable", Map.get(flags, :focusable))
      |> maybe_detail("focused", Map.get(flags, :focused))
      |> maybe_detail("default_focus", Map.get(focus_meta, :default_focus))
      |> maybe_detail("focus_scope", Map.get(focus_meta, :focus_scope))
      |> maybe_detail("implicit_owner", Map.get(focus_meta, :implicit_owner))
      |> maybe_detail("path", focus_path)
      |> maybe_detail("remembered", Map.get(selected, :remembered_focus))

    case details do
      [] -> "-"
      _ -> Enum.join(details, " ")
    end
  end

  defp flag_rows(nil), do: []

  defp flag_rows(%{flags: flags}) when is_list(flags) do
    flags
    |> Enum.map(fn
      {key, value} -> "#{key}: #{inspect(value)}"
      other -> inspect(other)
    end)
  end

  defp flag_rows(%{flags: flags}) when is_map(flags) do
    flags
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map(fn {key, value} -> "#{key}: #{inspect(value)}" end)
  end

  defp flag_rows(_selected), do: []

  defp fragment_line(nil), do: "-"

  defp fragment_line(%{fragment_preview: fragment_preview, fragment_size: fragment_size}) do
    "size=#{fragment_size} #{fragment_preview}"
  end

  defp fragment_render_line(nil, _screen), do: ""

  defp fragment_render_line(%{fragment_render: fragment_render}, screen) do
    width =
      case screen do
        %{width: screen_width} when is_integer(screen_width) -> max(screen_width - 2, 1)
        _ -> 78
      end

    fragment_render
    |> Kernel.||("")
    |> String.split("\n")
    |> Enum.map(&BackBreeze.String.truncate(&1, width))
    |> Enum.join("\n")
  end

  defp counts_line(%{counts: counts}) do
    "elements=#{counts.elements} focusables=#{counts.focusables} mouse_targets=#{counts.mouse_targets} children=#{counts.children}"
  end

  defp counts_line(_snapshot), do: "-"

  defp status_line(active, now) do
    snapshot = active.snapshot

    "updated=#{active.updated_at} age=#{age_text(now, active.updated_at)} render=#{snapshot.last_render_at || "-"} interaction=#{fmt_last_interaction(snapshot.last_interaction_at)}"
  end

  defp fmt_bounds(bounds) when bounds == %{}, do: "-"
  defp fmt_bounds(bounds), do: "#{bounds.left},#{bounds.top}->#{bounds.right},#{bounds.bottom}"

  defp fmt_padding(%{top: top, right: right, bottom: bottom, left: left}),
    do: "#{top}/#{right}/#{bottom}/#{left}"

  defp fmt_color(nil), do: "-"
  defp fmt_color({r, g, b}), do: hex_color(r, g, b)
  defp fmt_color(other), do: inspect(other)

  defp fmt_last_interaction(nil), do: "-"

  defp fmt_last_interaction(value) do
    "#{value}"
  end

  defp age_text(now, timestamp) when is_integer(now) and is_integer(timestamp) do
    "#{max(now - timestamp, 0)}ms"
  end

  defp age_text(_now, _timestamp), do: "-"

  defp hex_color(r, g, b) do
    "#" <>
      String.upcase(Base.encode16(<<r, g, b>>))
  end

  defp normalize_active_source(active_source, snapshots, latest_source) do
    cond do
      is_nil(active_source) -> latest_source
      not Map.has_key?(snapshots, active_source) -> latest_source
      source_alive?(snapshots, active_source) -> active_source
      source_alive?(snapshots, latest_source) -> latest_source
      true -> latest_source
    end
  end

  defp source_alive?(snapshots, source_key) do
    case Map.get(snapshots, source_key) do
      %{alive?: false} -> false
      %{} -> true
      _ -> false
    end
  end

  defp compact_inspect(value, width) do
    value
    |> inspect(pretty: true, limit: 8, printable_limit: width)
    |> String.replace("\n", " ")
    |> String.replace(~r/\s+/, " ")
    |> truncate(width)
  end

  defp truncate(text, width) when is_integer(width) and width > 3 do
    if String.length(text) > width do
      String.slice(text, 0, width - 3) <> "..."
    else
      text
    end
  end

  defp maybe_detail(details, _label, nil), do: details
  defp maybe_detail(details, label, value), do: details ++ ["#{label}=#{inspect(value)}"]

  defp string_length(value) when is_binary(value), do: String.length(value)
  defp string_length(_value), do: nil

  defp present_string(value) when is_binary(value) and value != "", do: true
  defp present_string(_value), do: nil
end
