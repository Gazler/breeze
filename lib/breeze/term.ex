defmodule Breeze.Term do
  @moduledoc """
  Opaque runtime context passed to Breeze view callbacks.

  Views receive this value in `mount/2`, `handle_event/3`, and `handle_info/2`.
  Treat its internal fields as implementation details and update it through
  helpers from `Breeze.View`, such as `assign/2`, `focus/2`, and
  `put_local_keybindings/2`.
  """

  @typedoc "Opaque state passed between Breeze view callbacks."
  @opaque t :: %__MODULE__{}

  defstruct [
    :view,
    :child_view_supervisor,
    :server,
    :terminal,
    :theme,
    :theme_source,
    :reader,
    last_render_at: nil,
    last_interaction_at: nil,
    assigns: %{},
    external_assigns: %{},
    global_keybindings: [],
    local_keybindings: [],
    focus_keybindings: %{},
    focused: nil,
    allow_unfocused?: false,
    focusables: [],
    focus_meta: %{},
    focus_memory: %{},
    elements: %{},
    retained_elements: %{},
    events: %{},
    implicit_state: %{},
    retained_implicit_state: %{},
    implicit_meta: %{},
    rendered_contents: %{},
    rendered_boxes: %{},
    input_routing_signature: nil,
    mouse_targets: %{},
    children: %{},
    frame_delay_ms: 16,
    render_timer: nil,
    render_tree?: false,
    apply_theme_defaults?: false
  ]
end
