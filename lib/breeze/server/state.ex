defmodule Breeze.Server.State.Input do
  @moduledoc false

  defstruct [
    :pending_ref,
    :pending_started_at,
    :pending_sync_child_render_id,
    queued_input: :queue.new(),
    flush_scheduled?: false
  ]
end

defmodule Breeze.Server.State.Frame do
  @moduledoc false

  defstruct [
    :last_payload,
    :last_lines,
    :inline_reserved_height,
    inline_history_height: 0,
    inline_history_lines: [],
    inline_history_scrollback: "",
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
            viewports: %{},
            mouse_targets: %{},
            flags: %{},
            focus_meta: %{},
            implicit_state: %{},
            implicit_meta: %{}
end
