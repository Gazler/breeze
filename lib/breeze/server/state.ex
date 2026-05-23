defmodule Breeze.Server.State.Input do
  @moduledoc false

  defstruct [
    :pending_ref,
    :pending_started_at,
    :pending_sync_child_render_id,
    queued_input: :queue.new(),
    flush_scheduled?: false,
    render_after_flush?: false
  ]
end

defmodule Breeze.Server.State.Frame do
  @moduledoc false

  defstruct [
    :last_payload,
    :last_lines,
    base_output: "",
    last_overlays: [],
    decorations: [],
    animation_timer: nil,
    next_tick_at: nil
  ]
end

defmodule Breeze.Server.State.Debug do
  @moduledoc false

  defstruct subscribers: MapSet.new(),
            stats: %{},
            push_timer: nil,
            push_interval_ms: 250,
            busy_delay_ms: 120,
            frame_delay_ms: 80
end

defmodule Breeze.Server.State.Inspector do
  @moduledoc false

  defstruct config: false,
            visible?: false,
            selected_id: nil,
            hovered_id: nil,
            panel_position: :bottom,
            subscribers: MapSet.new()
end

defmodule Breeze.Server.State.Rendered do
  @moduledoc false

  defstruct boxes: %{},
            elements: %{},
            render_tree: nil,
            render_tree_meta: %{},
            code_tree_meta: %{},
            viewports: %{},
            mouse_targets: %{},
            flags: %{},
            focus_meta: %{},
            implicit_state: %{},
            implicit_meta: %{}
end
