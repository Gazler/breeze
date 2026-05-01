defmodule Breeze.Term do
  @moduledoc false

  defstruct [
    :view,
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
    mouse_targets: %{},
    children: %{},
    frame_delay_ms: 16,
    render_timer: nil,
    apply_theme_defaults?: false
  ]
end
